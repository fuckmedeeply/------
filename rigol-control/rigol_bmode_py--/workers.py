from __future__ import annotations
import os, json, time
from datetime import datetime
from typing import Optional, List, Tuple

import numpy as np
from PySide6.QtCore import QObject, Signal, QThread
from scipy.signal import hilbert
from scipy.io import savemat

from utils.excel_io import write_wave_excel
from processing.trajectory_3d import env_to_db, mips


def _calculate_steps(total_diff: float, interval_dist: float) -> List[float]:
    if abs(total_diff) == 0:
        return []
    direction = 1.0 if total_diff > 0 else -1.0
    abs_diff = abs(total_diff)
    full_steps = int(abs_diff // interval_dist)
    remainder = abs_diff % interval_dist
    steps: List[float] = [direction * interval_dist] * full_steps
    if remainder > 1e-9:
        steps.append(direction * remainder)
    return steps


class AcquisitionWorker(QObject):
    new_frame = Signal(object)  # wave_v
    log = Signal(str)

    def __init__(self, scope, channel: int = 1, points: int = 1000):
        super().__init__()
        self.scope = scope
        self.channel = channel
        self.points = points
        self._thread: Optional[_AcqThread] = None
        self.is_running = False

    def start_continuous(self, interval_s: float = 0.5):
        if self.is_running:
            return
        self.is_running = True
        self._thread = _AcqThread(self, interval_s)
        self._thread.start()

    def stop(self):
        self.is_running = False


class _AcqThread(QThread):
    def __init__(self, p: AcquisitionWorker, interval_s: float):
        super().__init__()
        self.p = p
        self.interval_s = interval_s

    def run(self):
        self.p.log.emit("AUTO采集线程启动（NORM屏幕数据）")
        while self.p.is_running:
            try:
                wave_v, fs, n, time_s, meta = self.p.scope.acquire_screen_norm(channel=self.p.channel, points=self.p.points)
                self.p.new_frame.emit(wave_v)
            except Exception as e:
                self.p.log.emit(f"AUTO采集失败: {e}")
            time.sleep(self.interval_s)
        self.p.log.emit("AUTO采集线程退出")


class IntervalScanWorker(QObject):
    log = Signal(str)
    session_dir_ready = Signal(str)
    step_acquired = Signal(dict)
    progress = Signal(int, int)
    finished = Signal()
    failed = Signal(str)

    def __init__(self, scope, stage, save_dir: str, channel: int, points: int,
                 x_diff_mm: float, y_diff_mm: float, z_diff_mm: float,
                 interval_mm: float, pre_delay_s: float):
        super().__init__()
        self.scope = scope
        self.stage = stage
        self.save_dir = save_dir
        self.channel = int(channel)
        self.points = int(points)
        self.x_diff_mm = float(x_diff_mm)
        self.y_diff_mm = float(y_diff_mm)
        self.z_diff_mm = float(z_diff_mm)
        self.interval_mm = float(interval_mm)
        self.pre_delay_s = float(pre_delay_s)
        self._thread: Optional[_IntervalThread] = None
        self._stop = False
        self.is_running = False
        self.session_dir: Optional[str] = None

    def start(self):
        if self.is_running:
            return
        self._stop = False
        self.is_running = True
        self._thread = _IntervalThread(self)
        self._thread.start()

    def stop(self):
        self._stop = True

    def _should_stop(self):
        return self._stop


class _IntervalThread(QThread):
    def __init__(self, p: IntervalScanWorker):
        super().__init__()
        self.p = p

    def run(self):
        try:
            if not getattr(self.p.scope, 'is_connected', False):
                raise RuntimeError('示波器未连接')
            if not getattr(self.p.stage, 'is_connected', False):
                raise RuntimeError('三轴串口未连接')

            os.makedirs(self.p.save_dir, exist_ok=True)
            ts_session = datetime.now().strftime('%Y%m%d_%H%M%S')
            self.p.session_dir = os.path.join(self.p.save_dir, f'scan_{ts_session}')
            os.makedirs(self.p.session_dir, exist_ok=True)
            self.p.session_dir_ready.emit(self.p.session_dir)

            params = {'timestamp': ts_session, 'channel': self.p.channel, 'points_request': self.p.points,
                      'x_total_mm': self.p.x_diff_mm, 'y_total_mm': self.p.y_diff_mm, 'z_total_mm': self.p.z_diff_mm,
                      'interval_mm': self.p.interval_mm, 'pre_delay_s': self.p.pre_delay_s,
                      'wait_per_mm': float(getattr(self.p.stage, 'wait_per_mm', 0.5))}
            with open(os.path.join(self.p.session_dir, 'scan_params.json'), 'w', encoding='utf-8') as f:
                json.dump(params, f, ensure_ascii=False, indent=2)

            x_steps = _calculate_steps(self.p.x_diff_mm, self.p.interval_mm)
            y_steps = _calculate_steps(self.p.y_diff_mm, self.p.interval_mm)
            z_steps = _calculate_steps(self.p.z_diff_mm, self.p.interval_mm)
            max_steps = max(len(x_steps), len(y_steps), len(z_steps), 0)
            self.p.log.emit(f'间隔位移将分{max_steps}步完成，每步采前等待 {self.p.pre_delay_s} 秒')

            self._acquire_and_save('init', 0)

            for step in range(1, max_steps+1):
                if self.p._should_stop():
                    self.p.log.emit('间隔扫描已停止'); break
                dx = x_steps[step-1] if step-1 < len(x_steps) else 0.0
                dy = y_steps[step-1] if step-1 < len(y_steps) else 0.0
                dz = z_steps[step-1] if step-1 < len(z_steps) else 0.0

                # 1. 异步发送各轴位移命令（参考 MATLAB executeAxisMovementAsync）
                self.p.log.emit(f'第{step}/{max_steps}步: 开始位移 dx={dx:.3f} dy={dy:.3f} dz={dz:.3f} mm')
                if abs(dx) > 0.001: self.p.stage.move_axis_async('X', dx)
                if abs(dy) > 0.001: self.p.stage.move_axis_async('Y', dy)
                if abs(dz) > 0.001: self.p.stage.move_axis_async('Z', dz)

                # 2. 等待电机运动完成（pre_delay 覆盖电机运动时间）
                self.p.log.emit(f'第{step}/{max_steps}步: 等待 {self.p.pre_delay_s:.1f}s...')
                t0 = time.time()
                while time.time()-t0 < self.p.pre_delay_s:
                    if self.p._should_stop(): break
                    QThread.msleep(10)  # 10ms短间隔，更快响应
                if self.p._should_stop():
                    self.p.log.emit('间隔扫描已停止'); break

                # 3. 采集数据
                self.p.log.emit(f'第{step}/{max_steps}步: 开始采集')
                self._acquire_and_save('step', step)
                self.p.progress.emit(step, max_steps)

            self.p.finished.emit()
        except Exception as e:
            self.p.failed.emit(str(e))
        finally:
            self.p.is_running = False

    def _acquire_and_save(self, tag: str, step_index: int):
        wave_v, fs, n, time_s, meta = self.p.scope.acquire_screen_norm(channel=self.p.channel, points=self.p.points)
        ts = datetime.now().strftime('%Y%m%d_%H%M%S_%f')[:-3]
        x_mm = float(self.p.stage.current_mm.get('X', 0.0))
        y_mm = float(self.p.stage.current_mm.get('Y', 0.0))
        z_mm = float(self.p.stage.current_mm.get('Z', 0.0))
        filename = f'波形数据_{ts}_X={x_mm:.2f}_Y={y_mm:.2f}_Z={z_mm:.2f}.xlsx'
        filepath = os.path.join(self.p.session_dir or self.p.save_dir, filename)

        T = float(n)/float(fs) if fs>0 else 0.0
        F = 1.0/T if T>0 else 0.0
        metadata_pairs = [
            ('采样率(MSa/s)', fs/1_000_000.0),
            ('请求点数(k点)', self.p.points/1000.0),
            ('返回点数(k点)', n/1000.0),
            ('周期(s)', T),
            ('频率(Hz)', F),
            ('X位置(mm)', x_mm),
            ('Y位置(mm)', y_mm),
            ('Z位置(mm)', z_mm),
            ('', ''),
        ]
        write_wave_excel(filepath, metadata_pairs, time_s, wave_v)
        self.p.log.emit(f'{tag} 采集并保存: {filepath}')
        self.p.step_acquired.emit({'tag': tag, 'step_index': step_index, 'wave_v': wave_v, 'fs': fs, 'n': n,
                                  'time_s': time_s, 'x_mm': x_mm, 'y_mm': y_mm, 'z_mm': z_mm, 'excel_path': filepath})


class TrajectoryScanWorker(QObject):
    """
    Port of MATLAB executeTrajectoryScan() (S-shaped scan, ignore Z):
      - builds volumeEnv(depth, x, yLines) as single (float32) envelope
      - saves out struct to .mat: env, db, x_mm, y_mm, depth_mm, DR, contrastGain, timestamp
      - emits plane_update for each y line and mips_ready at end
    """
    log = Signal(str)
    session_dir_ready = Signal(str)
    plane_update = Signal(dict)      # {x_mm, depth_mm, img_db, line_idx, y_lines}
    point_acquired = Signal(dict)    # optional: {wave_v, x_mm,y_mm,z_mm, excel_path}
    finished = Signal(dict)          # {mat_path, mip_paths, session_dir}
    failed = Signal(str)
    progress = Signal(int, int)      # point_idx, total_points

    def __init__(self, scope, stage, save_dir: str, channel: int, points: int,
                 x_span_mm: float, x_step_mm: float, y_step_mm: float, y_lines: int,
                 start_at_current: bool = True, reset_bmode: bool = True, acquire_each_point: bool = True,
                 dr_db: float = 50.0, contrast_gain: float = 1.4, c_sound_m_s: float = 1540.0,
                 span_axis: str = "X", step_axis: str = "Y", pre_delay_s: float = 0.5):
        super().__init__()
        self.scope = scope
        self.stage = stage
        self.save_dir = save_dir
        self.channel = int(channel)
        self.points = int(points)
        self.x_span_mm = float(x_span_mm)
        self.x_step_mm = float(x_step_mm)
        self.y_step_mm = float(y_step_mm)
        self.y_lines = int(y_lines)
        self.start_at_current = bool(start_at_current)
        self.reset_bmode = bool(reset_bmode)
        self.acquire_each_point = bool(acquire_each_point)
        self.dr_db = float(dr_db)
        self.contrast_gain = float(contrast_gain)
        self.c_sound_m_s = float(c_sound_m_s)
        self.span_axis = str(span_axis).upper()  # 行程轴（行内移动）
        self.step_axis = str(step_axis).upper()  # 步距轴（行间移动）
        self.pre_delay_s = float(pre_delay_s)  # 采集前稳定等待时间

        self._thread: Optional[_TrajectoryThread] = None
        self._stop = False
        self.is_running = False
        self.session_dir: Optional[str] = None

    def start(self):
        if self.is_running:
            return
        self._stop = False
        self.is_running = True
        self._thread = _TrajectoryThread(self)
        self._thread.start()

    def stop(self):
        self._stop = True

    def _should_stop(self):
        return self._stop


class _TrajectoryThread(QThread):
    """轨迹扫描线程 - 类似间隔位移，但在行末拐点处同时移动X和Y"""
    def __init__(self, p: TrajectoryScanWorker):
        super().__init__()
        self.p = p

    def run(self):
        try:
            if not getattr(self.p.scope, 'is_connected', False):
                raise RuntimeError('示波器未连接')
            if not getattr(self.p.stage, 'is_connected', False):
                raise RuntimeError('三轴串口未连接')

            os.makedirs(self.p.save_dir, exist_ok=True)
            ts_session = datetime.now().strftime('%Y%m%d_%H%M%S')
            self.p.session_dir = os.path.join(self.p.save_dir, f'traj_{ts_session}')
            os.makedirs(self.p.session_dir, exist_ok=True)
            self.p.session_dir_ready.emit(self.p.session_dir)

            # 计算每行的点数
            x_step = self.p.x_step_mm if self.p.x_step_mm > 0 else self.p.x_span_mm
            points_per_line = max(1, int(self.p.x_span_mm // x_step) + 1)
            total_points = points_per_line * self.p.y_lines

            # 计算每一步的位移量（类似间隔位移的步距分割）
            x_steps = _calculate_steps(self.p.x_span_mm, x_step)

            span_axis = self.p.span_axis
            step_axis = self.p.step_axis
            self.p.log.emit(f'开始S型轨迹扫描：行数={self.p.y_lines}, 每行点数={points_per_line}, 总点数={total_points}')
            self.p.log.emit(f'行程轴={span_axis}(步距{x_step:.2f}mm), 步距轴={step_axis}(步距{self.p.y_step_mm:.2f}mm)')

            # 测试采集一次，确保示波器就绪
            self.p.log.emit('准备采集：测试示波器状态...')
            try:
                test_env, test_depth, _ = self._acquire_point(save_excel=False, retry=1)
                if test_env is not None:
                    self.p.log.emit(f'示波器就绪，采集测试成功')
                else:
                    self.p.log.emit('警告：采集测试返回空数据')
            except Exception as e:
                self.p.log.emit(f'警告：采集测试失败: {str(e)}，继续尝试...')

            # Track axes
            start_x = float(self.p.stage.current_mm.get('X', 0.0)) if self.p.start_at_current else 0.0
            start_y = float(self.p.stage.current_mm.get('Y', 0.0)) if self.p.start_at_current else 0.0

            span_axis = self.p.span_axis
            step_axis = self.p.step_axis

            # Move to start if needed
            if not self.p.start_at_current:
                # 计算到起点的位移（根据选择的轴）
                span_dist = start_x - float(self.p.stage.current_mm.get(span_axis, 0.0))
                step_dist = start_y - float(self.p.stage.current_mm.get(step_axis, 0.0))
                self._execute_step(span_dist, step_dist, "移动到起点", is_corner=True)

            volume_env = None  # (depth,x,y)
            depth_axis = None
            span_positions = []  # 行程轴位置列表
            step_positions = np.full((self.p.y_lines,), np.nan, dtype=np.float32)  # 步距轴位置

            point_idx = 0

            for line_idx in range(1, self.p.y_lines + 1):
                if self.p._should_stop():
                    self.p.log.emit('轨迹已停止')
                    break

                # 确定扫描方向（奇数行正向，偶数行反向）
                dir_sign = 1.0 if (line_idx % 2 == 1) else -1.0
                line_env_cols = []
                line_span_pos = []  # 当前行的行程轴位置

                self.p.log.emit(f'=== 第{line_idx}/{self.p.y_lines}行，方向:{"正向" if dir_sign>0 else "反向"} ({span_axis}{"+" if dir_sign>0 else "-"}) ===')

                for p_idx in range(1, points_per_line + 1):
                    if self.p._should_stop():
                        break

                    # 1. 采集当前点数据
                    self.p.log.emit(f'第{line_idx}行第{p_idx}/{points_per_line}点：采集数据')
                    env_col, depth_mm, payload = self._acquire_point(save_excel=self.p.acquire_each_point, retry=2)
                    point_idx += 1
                    self.p.progress.emit(point_idx, total_points)
                    if payload is not None:
                        # 添加网格索引信息用于透射成像
                        payload['line_idx'] = line_idx           # 行号（步距轴方向）
                        payload['point_idx'] = p_idx             # 行内点号（行程轴方向）
                        payload['dir_sign'] = dir_sign           # 扫描方向
                        payload['points_per_line'] = points_per_line  # 每行点数
                        self.p.point_acquired.emit(payload)

                    if env_col is not None:
                        # depth alignment
                        if depth_axis is None:
                            depth_axis = depth_mm.astype(np.float32)
                        if depth_axis is not None and env_col.size != depth_axis.size:
                            if env_col.size > depth_axis.size:
                                env_col = env_col[:depth_axis.size]
                            else:
                                env_col = np.pad(env_col, (0, depth_axis.size - env_col.size), constant_values=0.0)
                        line_env_cols.append(env_col.astype(np.float32))
                        line_span_pos.append(float(self.p.stage.current_mm.get(span_axis, 0.0)))

                    # 2. 判断是否是行内最后一个点
                    is_last_point_in_line = (p_idx == points_per_line)

                    if not is_last_point_in_line:
                        # 行内移动：沿当前方向移动一个步距
                        span_dist = dir_sign * x_step
                        self._execute_step(span_dist, 0.0, f"行内位移 {span_axis}{'+' if span_dist > 0 else ''}{span_dist:.2f}mm", is_corner=False)
                    elif line_idx < self.p.y_lines:
                        # 拐点（行末且不是最后一行）：步距轴进给（换行）
                        # 下一行会自动以相反方向扫描，不需要一次性回扫
                        step_dist = self.p.y_step_mm
                        self._execute_step(0.0, step_dist, f"换行 {step_axis}+{step_dist:.2f}mm", is_corner=True)

                if self.p._should_stop():
                    self.p.log.emit('轨迹已停止')
                    break

                if not line_env_cols:
                    continue

                # finalize line: sort by span axis position（确保图像顺序正确）
                order = np.argsort(np.array(line_span_pos, dtype=np.float32))
                span_sorted = np.array(line_span_pos, dtype=np.float32)[order]
                env_sorted = np.stack(line_env_cols, axis=1)[:, order]  # (depth, span)

                step_positions[line_idx - 1] = float(self.p.stage.current_mm.get(step_axis, 0.0))
                if volume_env is None:
                    volume_env = np.zeros((env_sorted.shape[0], env_sorted.shape[1], self.p.y_lines), dtype=np.float32)
                volume_env[:, :, line_idx - 1] = env_sorted
                if len(span_positions) == 0:
                    span_positions = span_sorted.tolist()

                # render plane with local max
                local_max = float(np.max(env_sorted)) if env_sorted.size else 0.0
                if not np.isfinite(local_max) or local_max <= 0:
                    local_max = np.finfo(np.float32).eps
                plane_db = env_to_db(env_sorted, ref=local_max, dr_db=self.p.dr_db, contrast_gain=self.p.contrast_gain)

                self.p.plane_update.emit({
                    "x_mm": span_sorted,  # 行程轴位置
                    "depth_mm": depth_axis,
                    "img_db": plane_db,
                    "line_idx": line_idx,
                    "y_lines": self.p.y_lines,
                })

            # finalize 3D
            if volume_env is None:
                raise RuntimeError("轨迹扫描未获得有效数据（volumeEnv为空）")

            global_max = float(np.max(volume_env))
            if not np.isfinite(global_max) or global_max <= 0:
                global_max = np.finfo(np.float32).eps
            volume_db = env_to_db(volume_env, ref=global_max, dr_db=self.p.dr_db, contrast_gain=self.p.contrast_gain)

            ts = datetime.now().strftime('%Y%m%d_%H%M%S_%f')[:-3]
            span_arr = np.array(span_positions, dtype=np.float32)
            step_arr = step_positions
            out = {
                "env": volume_env.astype(np.float32),
                "db": volume_db.astype(np.float32),
                "span_mm": span_arr,
                "step_mm": step_arr,
                "span_axis": self.p.span_axis,
                "step_axis": self.p.step_axis,
                "depth_mm": depth_axis.astype(np.float32),
                "DR": float(self.p.dr_db),
                "contrastGain": float(self.p.contrast_gain),
                "timestamp": ts,
            }
            mat_path = os.path.join(self.p.session_dir, f"Bmode3D_{ts}.mat")
            savemat(mat_path, {"out": out})

            # MIPs & save images
            mip_xy, mip_xz, mip_yz = mips(volume_db)
            mip_paths = {}
            try:
                import imageio.v2 as imageio
                def save_img(name, img):
                    norm = np.clip((img + self.p.dr_db) / self.p.dr_db, 0.0, 1.0)
                    u8 = (norm * 255.0).astype(np.uint8)
                    pth = os.path.join(self.p.session_dir, name)
                    imageio.imwrite(pth, u8)
                    return pth
                mip_paths["mip_xy_png"] = save_img("mip_xy.png", mip_xy.T)
                mip_paths["mip_xz_png"] = save_img("mip_xz.png", mip_xz)
                mip_paths["mip_yz_png"] = save_img("mip_yz.png", mip_yz)
            except Exception as e:
                self.p.log.emit(f"保存MIP PNG失败: {e}")

            self.p.finished.emit({"mat_path": mat_path, "mip_paths": mip_paths, "session_dir": self.p.session_dir})
        except Exception as e:
            self.p.failed.emit(str(e))
        finally:
            self.p.is_running = False

    def _execute_step(self, span_dist: float, step_dist: float, desc: str, is_corner: bool = False):
        """执行单步位移：发送命令 -> 等待 -> 更新位置（类似间隔位移）

        Args:
            span_dist: 行程轴位移量（行内移动方向）
            step_dist: 步距轴位移量（行间移动方向）
            desc: 位移描述
            is_corner: 是否是拐点（同时移动两轴）
        """
        if self.p._should_stop():
            return

        span_axis = self.p.span_axis
        step_axis = self.p.step_axis

        self.p.log.emit(f'执行步进: {desc} ({span_axis}={span_dist:.3f}mm, {step_axis}={step_dist:.3f}mm)')

        try:
            # 1. 同时发送各轴位移命令（异步）
            if abs(span_dist) > 0.001:
                self.p.log.emit(f'  -> 发送{span_axis}轴(行程)位移: {span_dist:.3f}mm')
                self.p.stage.move_axis_async(span_axis, span_dist)

            # 拐点时才移动步距轴
            if is_corner and abs(step_dist) > 0.001:
                self.p.log.emit(f'  -> 发送{step_axis}轴(步距)位移: {step_dist:.3f}mm')
                self.p.stage.move_axis_async(step_axis, step_dist)

            # 2. 等待电机运动完成（优化：短间隔轮询，更快响应）
            max_dist = max(abs(span_dist), abs(step_dist) if is_corner else 0)
            if max_dist > 0.001:
                # 先等待电机运动时间
                move_time = max_dist * self.p.stage.wait_per_mm
                self.p.log.emit(f'  -> 等待电机运动: {move_time:.2f}秒')
                t0 = time.time()
                while time.time() - t0 < move_time:
                    if self.p._should_stop():
                        return
                    QThread.msleep(10)  # 10ms 而非 50ms，更快响应

                # 额外等待振动稳定（采集前延迟）
                stable_time = self.p.pre_delay_s
                if stable_time > 0:
                    self.p.log.emit(f'  -> 等待振动稳定: {stable_time:.2f}秒')
                    t0 = time.time()
                    while time.time() - t0 < stable_time:
                        if self.p._should_stop():
                            return
                        QThread.msleep(10)  # 10ms 短间隔
                self.p.log.emit(f'  -> 位移完成，可以采集')

            # 3. 更新位置记录
            if abs(span_dist) > 0.001:
                self.p.stage.update_position(span_axis, span_dist)
            if is_corner and abs(step_dist) > 0.001:
                self.p.stage.update_position(step_axis, step_dist)

            self.p.log.emit(f'  -> 当前位置: {span_axis}={self.p.stage.current_mm[span_axis]:.2f}mm, {step_axis}={self.p.stage.current_mm[step_axis]:.2f}mm')

        except Exception as e:
            self.p.log.emit(f'步进执行异常: {str(e)}')
            raise

    def _acquire_point(self, save_excel: bool, retry: int = 2):
        """采集单个点数据，带重试机制"""
        last_error = None

        for attempt in range(retry + 1):
            try:
                if attempt > 0:
                    self.p.log.emit(f"  -> 采集重试 (第{attempt}次)...")
                    time.sleep(0.2)  # 重试前等待

                wave_v, fs, n, time_s, meta = self.p.scope.acquire_screen_norm(channel=self.p.channel, points=self.p.points)

                # 验证数据有效性
                if wave_v is None or len(wave_v) == 0:
                    raise RuntimeError("采集数据为空")

                w = wave_v.astype(np.float64)
                w = w - np.nanmean(w)
                env = np.abs(hilbert(w))
                env[~np.isfinite(env)] = 0.0
                depth_mm = (np.arange(n, dtype=np.float64) * (self.p.c_sound_m_s / (2.0 * fs)) * 1000.0).astype(np.float32)

                payload = None
                if save_excel:
                    ts = datetime.now().strftime('%Y%m%d_%H%M%S_%f')[:-3]
                    span_axis = self.p.span_axis
                    step_axis = self.p.step_axis
                    span_mm = float(self.p.stage.current_mm.get(span_axis, 0.0))
                    step_mm = float(self.p.stage.current_mm.get(step_axis, 0.0))
                    z_mm = float(self.p.stage.current_mm.get('Z', 0.0))

                    # 根据轴映射确定X/Y/Z位置
                    pos = {'X': 0.0, 'Y': 0.0, 'Z': z_mm}
                    pos[span_axis] = span_mm
                    pos[step_axis] = step_mm

                    filename = f'波形数据_{ts}_X={pos["X"]:.2f}_Y={pos["Y"]:.2f}_Z={pos["Z"]:.2f}.xlsx'
                    filepath = os.path.join(self.p.session_dir, filename)
                    T = float(n)/float(fs) if fs>0 else 0.0
                    F = 1.0/T if T>0 else 0.0
                    metadata_pairs = [
                        ('采样率(MSa/s)', fs/1_000_000.0),
                        ('请求点数(k点)', self.p.points/1000.0),
                        ('返回点数(k点)', n/1000.0),
                        ('周期(s)', T),
                        ('频率(Hz)', F),
                        ('X位置(mm)', pos['X']),
                        ('Y位置(mm)', pos['Y']),
                        ('Z位置(mm)', pos['Z']),
                        ('行程轴', span_axis),
                        ('步距轴', step_axis),
                        ('', ''),
                    ]
                    write_wave_excel(filepath, metadata_pairs, time_s, wave_v)
                    payload = {"wave_v": wave_v, "fs": fs, "n": n, "time_s": time_s, "excel_path": filepath,
                               "span_mm": span_mm, "step_mm": step_mm, "z_mm": z_mm, "ts": ts}
                return env.astype(np.float32), depth_mm, payload

            except Exception as e:
                last_error = str(e)
                self.p.log.emit(f"  -> 采集失败: {last_error}")
                if attempt < retry:
                    continue
                else:
                    raise RuntimeError(f"采集失败(重试{retry}次后): {last_error}")

        return None, None, None  # 不应该到达这里
