"""
信号预处理滤波模块 - 用于透射成像噪声抑制
包含：带通滤波、小波去噪、背景扣除
"""
from __future__ import annotations
import numpy as np
from typing import Optional, Tuple
from scipy import signal as sp_signal


class SignalFilter:
    """信号滤波器 - 抑制电机驱动噪声和电磁干扰"""

    def __init__(self, fs_hz: float = 1e6):
        """
        初始化滤波器

        Args:
            fs_hz: 采样率 (Hz)
        """
        self.fs_hz = float(fs_hz)
        self.background_signal: Optional[np.ndarray] = None
        self.filter_enabled = True

        # 默认滤波参数 - 针对250kHz探头优化
        self.bandpass_low = 150e3    # 带通下限 150 kHz (250kHz探头低频端)
        self.bandpass_high = 350e3   # 带通上限 350 kHz (250kHz探头高频端)
        self.motor_freq = 50.0       # 电机驱动基频 50 Hz
        self.notch_bandwidth = 10.0  # 陷波带宽 10 Hz
        self.notch_harmonics = [50, 100, 150, 200, 250]  # 需要陷波的谐波频率列表

    def set_background(self, bg_signal: np.ndarray):
        """设置背景参考信号用于扣除"""
        self.background_signal = np.asarray(bg_signal, dtype=np.float64)

    def bandpass_filter(self, wave: np.ndarray,
                        f_low: Optional[float] = None,
                        f_high: Optional[float] = None) -> np.ndarray:
        """
        带通滤波 - 滤除电机驱动低频和高频噪声

        Args:
            wave: 输入波形
            f_low: 下限频率 (Hz)，默认100kHz
            f_high: 上限频率 (Hz)，默认5MHz

        Returns:
            滤波后波形
        """
        if not self.filter_enabled:
            return wave

        f_low = f_low if f_low is not None else self.bandpass_low
        f_high = f_high if f_high is not None else self.bandpass_high

        # 设计Butterworth带通滤波器
        nyq = self.fs_hz / 2.0
        low = max(f_low, 1.0) / nyq
        high = min(f_high, nyq - 1.0) / nyq

        if low >= high:
            return wave

        try:
            # 6阶Butterworth带通滤波器，更陡峭的滚降
            b, a = sp_signal.butter(6, [low, high], btype='band')
            filtered = sp_signal.filtfilt(b, a, wave)
            return filtered
        except Exception as e:
            print(f"[SignalFilter] 带通滤波失败: {e}")
            return wave

    def notch_filter_motor(self, wave: np.ndarray,
                           motor_freq: Optional[float] = None,
                           harmonics: Optional[list] = None) -> np.ndarray:
        """
        陷波滤波 - 滤除电机驱动频率及其谐波

        Args:
            wave: 输入波形
            motor_freq: 电机基频 (Hz)，默认50Hz（保留参数兼容性）
            harmonics: 谐波频率列表，默认使用 self.notch_harmonics

        Returns:
            滤波后波形
        """
        if not self.filter_enabled:
            return wave

        # 使用配置的谐波列表
        freq_list = harmonics if harmonics is not None else self.notch_harmonics

        result = np.asarray(wave, dtype=np.float64).copy()
        nyq = self.fs_hz / 2.0

        for f0 in freq_list:
            if f0 >= nyq:
                continue

            # 设计陷波器，Q值越高陷波越窄
            try:
                # Q = f0 / bandwidth，使用30作为Q值获得较窄的陷波
                Q = 30.0
                f_norm = f0 / nyq
                b, a = sp_signal.iirnotch(f_norm, Q)
                result = sp_signal.filtfilt(b, a, result)
            except Exception as e:
                print(f"[SignalFilter] 陷波滤波({f0}Hz)失败: {e}")

        return result

    def wavelet_denoise(self, wave: np.ndarray,
                        wavelet: str = 'db4',
                        level: int = 3,
                        threshold_factor: float = 2.0) -> np.ndarray:
        """
        小波阈值去噪 - 时域信号平滑

        Args:
            wave: 输入波形
            wavelet: 小波基函数
            level: 分解层数
            threshold_factor: 阈值系数

        Returns:
            去噪后波形
        """
        if not self.filter_enabled:
            return wave

        try:
            import pywt

            w = np.asarray(wave, dtype=np.float64)

            # 小波分解
            coeffs = pywt.wavedec(w, wavelet, level=level)

            # 计算阈值
            sigma = np.median(np.abs(coeffs[-1])) / 0.6745
            threshold = threshold_factor * sigma

            # 软阈值处理
            denoised_coeffs = [coeffs[0]]  # 保留近似系数
            for detail in coeffs[1:]:
                # 软阈值函数
                detail_denoised = np.sign(detail) * np.maximum(np.abs(detail) - threshold, 0)
                denoised_coeffs.append(detail_denoised)

            # 重构信号
            reconstructed = pywt.waverec(denoised_coeffs, wavelet)

            # 确保长度一致
            if len(reconstructed) > len(w):
                reconstructed = reconstructed[:len(w)]
            elif len(reconstructed) < len(w):
                reconstructed = np.pad(reconstructed, (0, len(w) - len(reconstructed)))

            return reconstructed

        except ImportError:
            print("[SignalFilter] 未安装PyWavelets，使用备选平滑方法")
            # 使用Savitzky-Golay或移动平均作为备选
            return self.savgol_smooth(wave)
        except Exception as e:
            print(f"[SignalFilter] 小波去噪失败: {e}，使用备选平滑方法")
            return self.savgol_smooth(wave)

    def savgol_smooth(self, wave: np.ndarray, window_length: int = 11, polyorder: int = 3) -> np.ndarray:
        """
        Savitzky-Golay平滑滤波 - 保留峰值特征
        不依赖PyWavelets，作为小波去噪的备选方案

        Args:
            wave: 输入波形
            window_length: 窗口长度（奇数）
            polyorder: 多项式阶数

        Returns:
            平滑后波形
        """
        if not self.filter_enabled:
            return wave

        try:
            from scipy.signal import savgol_filter
            w = np.asarray(wave, dtype=np.float64)
            # 确保窗口长度合适
            if len(w) < window_length:
                window_length = min(len(w) // 2 * 2 + 1, 5)  # 确保是奇数且至少为5
            if window_length < polyorder + 1:
                window_length = polyorder + 2 if polyorder % 2 == 0 else polyorder + 1
            return savgol_filter(w, window_length, polyorder)
        except Exception as e:
            print(f"[SignalFilter] Savitzky-Golay平滑失败: {e}，使用移动平均")
            return self.moving_average_smooth(wave)

    def moving_average_smooth(self, wave: np.ndarray, window_size: int = 5) -> np.ndarray:
        """
        移动平均平滑 - 最简单的平滑方法
        作为所有其他方法的最终备选

        Args:
            wave: 输入波形
            window_size: 窗口大小

        Returns:
            平滑后波形
        """
        if not self.filter_enabled:
            return wave

        try:
            w = np.asarray(wave, dtype=np.float64)
            if len(w) < window_size:
                return w
            # 使用卷积实现移动平均
            kernel = np.ones(window_size) / window_size
            smoothed = np.convolve(w, kernel, mode='same')
            return smoothed
        except Exception as e:
            print(f"[SignalFilter] 移动平均平滑失败: {e}")
            return wave

    def kalman_smooth(self, wave: np.ndarray,
                      process_noise: float = 1e-5,
                      measurement_noise: float = 1e-3) -> np.ndarray:
        """
        自适应卡尔曼滤波 - 平滑时域信号

        Args:
            wave: 输入波形
            process_noise: 过程噪声协方差
            measurement_noise: 测量噪声协方差

        Returns:
            平滑后波形
        """
        if not self.filter_enabled:
            return wave

        try:
            w = np.asarray(wave, dtype=np.float64)
            n = len(w)

            # 初始化卡尔曼滤波器
            x_hat = np.zeros(n)  # 状态估计
            P = 1.0              # 估计误差协方差
            Q = process_noise    # 过程噪声
            R = measurement_noise  # 测量噪声

            x_hat[0] = w[0]

            for k in range(1, n):
                # 预测
                x_pred = x_hat[k-1]
                P_pred = P + Q

                # 更新
                K = P_pred / (P_pred + R)  # 卡尔曼增益
                x_hat[k] = x_pred + K * (w[k] - x_pred)
                P = (1 - K) * P_pred

            return x_hat

        except Exception as e:
            print(f"[SignalFilter] 卡尔曼滤波失败: {e}")
            return wave

    def remove_spikes(self, wave: np.ndarray, kernel_size: int = 5) -> np.ndarray:
        """
        中值滤波去除尖峰/脉冲噪声

        Args:
            wave: 输入波形
            kernel_size: 中值滤波窗口大小（奇数，越大去除越激进）

        Returns:
            去除尖峰后的波形
        """
        if not self.filter_enabled:
            return wave

        try:
            from scipy.signal import medfilt
            w = np.asarray(wave, dtype=np.float64)
            if kernel_size % 2 == 0:
                kernel_size += 1
            kernel_size = max(3, min(kernel_size, len(w) // 2 * 2 - 1))
            return medfilt(w, kernel_size=kernel_size)
        except Exception as e:
            print(f"[SignalFilter] 去尖峰滤波失败: {e}")
            return wave

    def background_subtraction(self, wave: np.ndarray) -> np.ndarray:
        """
        背景扣除 - 消除系统性噪声基底

        Args:
            wave: 输入波形

        Returns:
            背景扣除后波形
        """
        if not self.filter_enabled or self.background_signal is None:
            return wave

        try:
            w = np.asarray(wave, dtype=np.float64)
            bg = np.asarray(self.background_signal, dtype=np.float64)

            # 确保长度一致
            if len(bg) != len(w):
                if len(bg) > len(w):
                    bg = bg[:len(w)]
                else:
                    bg = np.pad(bg, (0, len(w) - len(bg)))

            # 背景扣除
            result = w - bg

            # 去除直流偏移
            result = result - np.mean(result)

            return result

        except Exception as e:
            print(f"[SignalFilter] 背景扣除失败: {e}")
            return wave

    def full_process(self, wave: np.ndarray,
                     use_bandpass: bool = True,
                     use_notch: bool = True,
                     use_wavelet: bool = True,
                     use_kalman: bool = False,
                     use_bg_sub: bool = True) -> np.ndarray:
        """
        完整预处理流程

        Args:
            wave: 原始输入波形
            use_bandpass: 是否使用带通滤波
            use_notch: 是否使用陷波滤波
            use_wavelet: 是否使用小波去噪
            use_kalman: 是否使用卡尔曼滤波（与小波二选一）
            use_bg_sub: 是否使用背景扣除

        Returns:
            完整处理后波形
        """
        if not self.filter_enabled:
            return wave

        result = np.asarray(wave, dtype=np.float64)

        # 1. 背景扣除（首先进行，去除系统性噪声）
        if use_bg_sub:
            result = self.background_subtraction(result)

        # 2. 陷波滤波（滤除电机驱动频率）
        if use_notch:
            result = self.notch_filter_motor(result)

        # 3. 带通滤波（频带限制）
        if use_bandpass:
            result = self.bandpass_filter(result)

        # 4. 时域平滑（小波或卡尔曼或Savitzky-Golay，三选一）
        if use_wavelet:
            result = self.wavelet_denoise(result)
        elif use_kalman:
            result = self.kalman_smooth(result)
        else:
            # 默认使用Savitzky-Golay平滑（不依赖PyWavelets）
            result = self.savgol_smooth(result)

        return result

    def full_process_250khz(self, wave: np.ndarray,
                            use_notch: bool = True,
                            use_savgol: bool = True,
                            use_bg_sub: bool = True) -> np.ndarray:
        """
        针对250kHz探头的优化滤波流程
        使用150-350kHz带通，多谐波陷波，Savitzky-Golay平滑

        Args:
            wave: 原始输入波形
            use_notch: 是否使用多谐波陷波（50,100,150,200,250Hz）
            use_savgol: 是否使用Savitzky-Golay平滑
            use_bg_sub: 是否使用背景扣除

        Returns:
            滤波后波形
        """
        if not self.filter_enabled:
            return wave

        result = np.asarray(wave, dtype=np.float64)

        # 1. 背景扣除
        if use_bg_sub:
            result = self.background_subtraction(result)

        # 2. 多谐波陷波（50Hz及其多次谐波）
        if use_notch:
            result = self.notch_filter_motor(result)

        # 3. 严格带通滤波（150-350kHz，针对250kHz探头）
        result = self.bandpass_filter(result, f_low=150e3, f_high=350e3)

        # 4. Savitzky-Golay平滑（保留峰值特征）
        if use_savgol:
            result = self.savgol_smooth(result)

        return result


def quick_filter(wave: np.ndarray, fs_hz: float,
                 motor_freq: float = 50.0) -> np.ndarray:
    """
    快速滤波接口 - 使用默认参数进行完整滤波

    Args:
        wave: 输入波形
        fs_hz: 采样率
        motor_freq: 电机驱动频率

    Returns:
        滤波后波形
    """
    flt = SignalFilter(fs_hz)
    flt.motor_freq = motor_freq
    return flt.full_process(wave,
                           use_bandpass=True,
                           use_notch=True,
                           use_wavelet=True,
                           use_kalman=False,
                           use_bg_sub=False)
