from __future__ import annotations
import os
import sys
import json
import shutil
import time
from datetime import datetime

import numpy as np
import pyqtgraph as pg
from PySide6.QtCore import Qt, QTimer, QPropertyAnimation, QEasingCurve, QRect, QRectF, QSize, Signal
from PySide6.QtGui import (
    QAction, QIcon, QKeySequence, QPainter, QColor, QLinearGradient,
    QBrush, QPen, QFont, QFontDatabase
)
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QLabel, QPushButton, QLineEdit,
    QComboBox, QTextEdit, QGroupBox, QFileDialog, QMessageBox, QGridLayout,
    QHBoxLayout, QVBoxLayout, QDialog, QDialogButtonBox, QFormLayout,
    QScrollArea, QSplitter, QToolButton, QTabWidget, QSlider, QProgressBar,
    QSizePolicy, QFrame, QStackedWidget, QCheckBox, QSpinBox
)
from serial.tools import list_ports

from controllers.rigol_scope import RigolScope
from controllers.rs485_stage import RS485Stage3Axis
from processing.bmode_cache_matlab import BModeCacheMatlab
from processing.signal_filter import SignalFilter, quick_filter
from workers import AcquisitionWorker, IntervalScanWorker, TrajectoryScanWorker

# ═══════════════════════════ 优化后的配色系统 ═══════════════════════════
# 背景层级系统 - 增强深度感
BG       = "#0A0F1A"  # 最底层背景（更深）
PANEL    = "#0F1623"  # 主面板
PANEL2   = "#141B2D"  # 卡片/输入框
PANEL3   = "#1A2337"  # 悬浮/激活状态
BORDER   = "#1F3353"  # 边框
BORDER_A = "#2563EB"  # 激活边框

# 主题色 - 科技蓝渐变系统
ACCENT   = "#3B82F6"  # 主色调
ACCENT2  = "#06B6D4"  # 青色强调
ACCENT_LIGHT = "#60A5FA"  # 浅蓝
ACCENT_DARK  = "#1D4ED8"  # 深蓝

# 文字系统
TEXT     = "#F1F5F9"  # 主文字（更亮）
TEXT_DIM = "#E2E8F0"  # 次要文字
MUTED    = "#64748B"  # 辅助文字
MUTED2   = "#94A3B8"  # 标签文字

# 功能色 - 语义化增强
OK       = "#10B981"  # 成功（柔和绿）
WARN     = "#F59E0B"  # 警告（琥珀色）
BAD      = "#EF4444"  # 错误（柔和红）
INFO     = "#06B6D4"  # 信息（青色）
RUNNING  = "#8B5CF6"  # 运行中（紫色）

# 渐变色定义
GRADIENT_PRIMARY = f"qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 {ACCENT_DARK}, stop:1 {ACCENT})"
GRADIENT_PANEL = f"qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 {PANEL}, stop:1 {BG})"

# ─────────────────────────── Helpers ─────────────────────────────
def _safe_float(s, default=0.0):
    try:
        return float(str(s).strip())
    except Exception:
        return default

def _safe_int(s, default=0):
    try:
        return int(float(str(s).strip()))
    except Exception:
        return default

def human_bytes(n: int) -> str:
    n = int(max(0, n))
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if n < 1024:
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} PB"


# ─────────────────────────── StatusLamp ──────────────────────────
class StatusLamp(QWidget):
    """增强版 LED 指示灯 - 带呼吸动画效果"""
    def __init__(self, color_hex: str = "#374151", parent=None):
        super().__init__(parent)
        self._color = color_hex
        self._glow = False
        self._pulse_opacity = 1.0
        self.setFixedSize(14, 14)  # 稍微增大
        
        # 呼吸动画
        self._pulse_timer = QTimer(self)
        self._pulse_timer.timeout.connect(self._update_pulse)
        self._pulse_direction = 1
        self._pulse_speed = 0.03

    def set_color(self, color_hex: str, glow: bool = False):
        self._color = color_hex
        self._glow = glow
        if glow:
            self._pulse_timer.start(50)  # 20 FPS
        else:
            self._pulse_timer.stop()
            self._pulse_opacity = 1.0
        self.update()
    
    def _update_pulse(self):
        """呼吸效果更新"""
        self._pulse_opacity += self._pulse_direction * self._pulse_speed
        if self._pulse_opacity >= 1.0:
            self._pulse_opacity = 1.0
            self._pulse_direction = -1
        elif self._pulse_opacity <= 0.4:
            self._pulse_opacity = 0.4
            self._pulse_direction = 1
        self.update()

    def paintEvent(self, e):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing, True)
        c = QColor(self._color)
        
        # 外发光效果（多层）
        if self._glow:
            for i in range(3):
                glow_c = QColor(c)
                alpha = int(40 * self._pulse_opacity * (1 - i * 0.3))
                glow_c.setAlpha(alpha)
                p.setBrush(QBrush(glow_c))
                p.setPen(Qt.NoPen)
                expand = (i + 1) * 2
                p.drawEllipse(self.rect().adjusted(-expand, -expand, expand, expand))
        
        # 主体
        r = self.rect().adjusted(2, 2, -2, -2)
        gradient = QLinearGradient(r.topLeft(), r.bottomRight())
        gradient.setColorAt(0, c.lighter(130))
        gradient.setColorAt(1, c)
        p.setBrush(QBrush(gradient))
        p.setPen(QPen(c.lighter(180), 1))
        p.drawEllipse(r)
        
        # 高光
        highlight = QColor(255, 255, 255, int(100 * self._pulse_opacity))
        p.setBrush(QBrush(highlight))
        p.setPen(Qt.NoPen)
        highlight_rect = r.adjusted(2, 2, -4, -4)
        p.drawEllipse(highlight_rect)


# ─────────────────────────── CollapsibleBox ──────────────────────
class CollapsibleBox(QWidget):
    """优化版折叠面板 - 增强视觉层次"""
    def __init__(self, title: str, parent=None, expanded=True):
        super().__init__(parent)
        self.toggle = QToolButton(checkable=True, checked=expanded)
        self.toggle.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
        self.toggle.setArrowType(Qt.DownArrow if expanded else Qt.RightArrow)
        self.toggle.setText(f"  {title}")
        self.toggle.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        self.toggle.setFixedHeight(42)  # 增加高度
        self.toggle.clicked.connect(self._on_toggled)

        self.content = QWidget()
        self.content.setVisible(expanded)
        if not expanded:
            self.content.setMaximumHeight(0)

        self.anim = QPropertyAnimation(self.content, b"maximumHeight")
        self.anim.setDuration(250)  # 稍微加快动画
        self.anim.setEasingCurve(QEasingCurve.OutCubic)

        # 添加分隔线
        sep = QFrame()
        sep.setFrameShape(QFrame.HLine)
        sep.setFixedHeight(1)
        sep.setStyleSheet(f"background: {BORDER}; border: none;")

        lay = QVBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 8)  # 增加底部间距
        lay.setSpacing(0)
        lay.addWidget(self.toggle)
        lay.addWidget(sep)
        lay.addWidget(self.content)

    def setContentLayout(self, layout):
        layout.setContentsMargins(10, 10, 10, 10)  # 优化：缩小内边距 12→10
        self.content.setLayout(layout)
        if self.toggle.isChecked():
            self.content.setMaximumHeight(16777215)

    def _on_toggled(self, checked: bool):
        self.toggle.setArrowType(Qt.DownArrow if checked else Qt.RightArrow)
        self.content.setVisible(True)
        start = self.content.height()
        end = self.content.sizeHint().height() if checked else 0
        self.anim.stop()
        self.anim.setStartValue(start)
        self.anim.setEndValue(end)
        self.anim.finished.connect(lambda: (
            self.content.setVisible(checked),
            self.content.setMaximumHeight(16777215) if checked else None
        ))
        self.anim.start()


# ─────────────────────────── LogView ─────────────────────────────
class LogView(QTextEdit):
    """优化版日志视图 - 增强可读性"""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setReadOnly(True)
        # 使用更现代的等宽字体
        try:
            font = QFont("JetBrains Mono", 10)
            if not font.exactMatch():
                font = QFont("Consolas", 10)
        except:
            font = QFont("Consolas", 10)
        self.setFont(font)
        self.setLineWrapMode(QTextEdit.NoWrap)  # 禁止自动换行

    def log(self, level: str, msg: str):
        ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]  # 添加毫秒
        lvl = level.lower()
        
        # 优化配色方案
        color_map = {
            "warn": (WARN, "WARN"),
            "warning": (WARN, "WARN"),
            "error": (BAD, "ERR "),
            "err": (BAD, "ERR "),
            "ok": (OK, " OK "),
            "success": (OK, " OK "),
            "info": (INFO, "INFO"),
            "debug": (MUTED2, "DEBG"),
        }
        
        color, tag = color_map.get(lvl, (MUTED2, lvl.upper().ljust(4)))
        
        html = (
            f'<div style="margin: 2px 0; padding: 4px 8px; background: rgba(255,255,255,0.02); border-left: 3px solid {color};">'
            f'<span style="color:{MUTED};font-family:Consolas;font-size:10px;">{ts}</span> '
            f'<span style="color:{color};font-weight:700;font-family:Consolas;font-size:11px;">[{tag}]</span> '
            f'<span style="color:{TEXT};font-family:Consolas;font-size:11px;">{msg}</span>'
            f'</div>'
        )
        self.append(html)
        # 自动滚动到底部
        self.verticalScrollBar().setValue(self.verticalScrollBar().maximum())


# ─────────────────────────── EditableValueLabel ──────────────────
class EditableValueLabel(QLabel):
    def __init__(self, text: str, *, unit="", parse=float, fmt="{:.2f}", on_set=None, parent=None):
        super().__init__(text, parent)
        self._unit = unit
        self._parse = parse
        self._fmt = fmt
        self._on_set = on_set
        self.setCursor(Qt.IBeamCursor)
        self.setToolTip("双击输入数值")

    def mouseDoubleClickEvent(self, e):
        from PySide6.QtWidgets import QInputDialog
        cur = self.text().replace(self._unit, "").replace("×", "").replace("dB", "").strip()
        val, ok = QInputDialog.getText(self, "输入数值", f"请输入数值({self._unit})：", text=cur)
        if ok:
            try:
                v = self._parse(val)
                suffix = f" {self._unit}".strip()
                self.setText((self._fmt.format(v) + (" " + suffix if suffix else "")).strip())
                if callable(self._on_set):
                    self._on_set(v)
            except Exception:
                pass
        return super().mouseDoubleClickEvent(e)


# ─────────────────────────── SerialSettingsDialog ────────────────
class SerialSettingsDialog(QDialog):
    def __init__(self, parent=None, cfg=None):
        super().__init__(parent)
        self.setWindowTitle("串口设置")
        self.setModal(True)
        self.resize(520, 340)

        default = {"x_port": "COM20", "y_port": "COM21", "z_port": "COM22",
                   "baudrate": 19200, "parity": "even", "stopbits": 1, "databits": 8}
        if isinstance(cfg, dict):
            default.update(cfg)
        self._cfg = default

        lay = QFormLayout(self)
        lay.setSpacing(12)

        self.x_port = QComboBox(); self.x_port.setEditable(True)
        self.y_port = QComboBox(); self.y_port.setEditable(True)
        self.z_port = QComboBox(); self.z_port.setEditable(True)
        self._fill_ports()
        self.x_port.setCurrentText(str(default["x_port"]))
        self.y_port.setCurrentText(str(default["y_port"]))
        self.z_port.setCurrentText(str(default["z_port"]))

        self.btn_refresh = QToolButton()
        self.btn_refresh.setText("⟳  刷新端口")
        self.btn_refresh.clicked.connect(self._fill_ports)

        self.baud = QLineEdit(str(default["baudrate"]))
        self.parity = QComboBox()
        self.parity.addItems(["even", "none", "odd"])
        self.parity.setCurrentText(str(default["parity"]).lower())
        self.stopbits = QComboBox()
        self.stopbits.addItems(["1", "2"])
        self.stopbits.setCurrentText(str(int(default["stopbits"])))
        self.databits = QComboBox()
        self.databits.addItems(["7", "8"])
        self.databits.setCurrentText(str(int(default["databits"])))

        lay.addRow("X 轴串口", self.x_port)
        lay.addRow("Y 轴串口", self.y_port)
        lay.addRow("Z 轴串口", self.z_port)
        lay.addRow("", self.btn_refresh)
        lay.addRow("波特率", self.baud)
        lay.addRow("校验位", self.parity)
        lay.addRow("停止位", self.stopbits)
        lay.addRow("数据位", self.databits)

        btns = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        btns.accepted.connect(self.accept)
        btns.rejected.connect(self.reject)
        lay.addRow(btns)

    def _fill_ports(self):
        curx, cury, curz = self.x_port.currentText(), self.y_port.currentText(), self.z_port.currentText()
        ports = []
        try:
            ports = [(p.device, p.description) for p in list_ports.comports()]
        except Exception:
            ports = []
        display, devices = [], []
        for dev, desc in ports:
            devices.append(dev)
            display.append(f"{dev}  |  {desc}")
        if not devices:
            devices = ["COM20", "COM21", "COM22"]
            display = devices[:]

        def normalize(cur_text):
            t = (cur_text or "").strip()
            if "COM" in t and "|" in t:
                return t.split("|", 1)[0].strip()
            return t if "COM" in t else ""

        def refill(cb, cur):
            cb.blockSignals(True)
            cb.clear()
            cb.addItems(display)
            cb.setCurrentText(cur)
            cb.blockSignals(False)

        x = normalize(curx) or self._cfg.get("x_port", "COM20")
        y = normalize(cury) or self._cfg.get("y_port", "COM21")
        z = normalize(curz) or self._cfg.get("z_port", "COM22")
        refill(self.x_port, next((d for d in display if d.startswith(x)), x))
        refill(self.y_port, next((d for d in display if d.startswith(y)), y))
        refill(self.z_port, next((d for d in display if d.startswith(z)), z))

    def get_config(self):
        def dev_text(cb):
            t = cb.currentText().strip()
            return t.split("|", 1)[0].strip() if "|" in t else t
        return {
            "x_port": dev_text(self.x_port),
            "y_port": dev_text(self.y_port),
            "z_port": dev_text(self.z_port),
            "baudrate": _safe_int(self.baud.text(), 19200),
            "parity": self.parity.currentText().strip().lower(),
            "stopbits": _safe_int(self.stopbits.currentText(), 1),
            "databits": _safe_int(self.databits.currentText(), 8),
        }


# ─────────────────────────── PresetStore ─────────────────────────
class PresetStore:
    def __init__(self, path: str):
        self.path = path
        self.data = {"visa_presets": [], "serial_presets": [], "acq_presets": []}
        self.load()

    def load(self):
        try:
            if os.path.exists(self.path):
                with open(self.path, "r", encoding="utf-8") as f:
                    self.data = json.load(f)
        except Exception:
            self.data = {"visa_presets": [], "serial_presets": [], "acq_presets": []}

    def save(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(self.data, f, ensure_ascii=False, indent=2)


# ─────────────────────────── InfoChip ────────────────────────────
class InfoChip(QWidget):
    """Pill-shaped status info chip for the bottom bar."""
    def __init__(self, icon: str, text: str, parent=None):
        super().__init__(parent)
        lay = QHBoxLayout(self)
        lay.setContentsMargins(10, 4, 12, 4)
        lay.setSpacing(6)
        self._icon_lbl = QLabel(icon)
        self._icon_lbl.setStyleSheet(f"color:{ACCENT2}; font-size:13px; background:transparent;")
        self._text_lbl = QLabel(text)
        self._text_lbl.setStyleSheet(f"color:{MUTED2}; font-size:11px; background:transparent;")
        lay.addWidget(self._icon_lbl)
        lay.addWidget(self._text_lbl)
        self.setStyleSheet(f"""
            InfoChip {{
                background: {PANEL3};
                border: 1px solid {BORDER};
                border-radius: 14px;
            }}
        """)

    def set_text(self, text: str, color: str = None):
        self._text_lbl.setText(text)
        if color:
            self._text_lbl.setStyleSheet(f"color:{color}; font-size:11px; background:transparent;")
        else:
            self._text_lbl.setStyleSheet(f"color:{MUTED2}; font-size:11px; background:transparent;")


# ─────────────────────────── SliderRow ───────────────────────────
class SliderRow(QWidget):
    """Labeled slider with inline live value display."""
    valueChanged = Signal(int)

    def __init__(self, label: str, lo: int, hi: int, val: int, unit: str = "", fmt: str = "{}", parent=None):
        super().__init__(parent)
        self._unit = unit
        self._fmt = fmt
        lay = QHBoxLayout(self)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.setSpacing(8)

        lbl = QLabel(label)
        lbl.setFixedWidth(52)
        lbl.setStyleSheet(f"color:{MUTED2}; font-size:11px; background:transparent;")

        self.slider = QSlider(Qt.Horizontal)
        self.slider.setRange(lo, hi)
        self.slider.setValue(val)

        self.val_lbl = QLabel(self._render(val))
        self.val_lbl.setFixedWidth(58)
        self.val_lbl.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.val_lbl.setStyleSheet(f"color:{ACCENT}; font-size:11px; font-weight:600; background:transparent;")

        self.slider.valueChanged.connect(self._on_changed)

        lay.addWidget(lbl)
        lay.addWidget(self.slider, 1)
        lay.addWidget(self.val_lbl)

    def _render(self, v):
        try:
            return self._fmt.format(v) + (f" {self._unit}" if self._unit else "")
        except Exception:
            return str(v)

    def _on_changed(self, v):
        self.val_lbl.setText(self._render(v))
        self.valueChanged.emit(v)

    def value(self):
        return self.slider.value()

    def setValue(self, v):
        self.slider.setValue(v)


# ─────────────────────────── MainWindow ──────────────────────────
class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("超声扫描成像系统")
        self.resize(1720, 1000)

        # Core objects
        self.scope = RigolScope()
        self.stage = RS485Stage3Axis()
        self.bmode_cache = BModeCacheMatlab(dr_db=50.0, contrast_gain=1.4, c_sound_m_s=1540.0)
        
        # 双探头透射成像模式
        self.imaging_mode = "transmission"  # 默认透射成像模式
        self.transmission_time_range = (0.0, 10.0)  # (start_us, end_us) 单位：µs，时间范围
        self.transmission_data = []  # 存储透射成像数据：[(x, y, vpp), ...]
        self.transmission_grid = {}  # 存储网格数据：{(x_idx, y_idx): vpp}
        self.transmission_step_x = 1.0  # X方向步距 (mm)
        self.transmission_step_y = 1.0  # Y方向步距 (mm)
        self._transmission_span_axis = "X"    # 最近一次透射成像的行程轴
        self._transmission_step_axis = "Y"    # 最近一次透射成像的步距轴
        self._transmission_span_step = 1.0    # 最近一次透射成像的行程步距 (mm)
        self._transmission_step_step = 1.0    # 最近一次透射成像的步距步距 (mm)
        self._vpp_text_items: list = []  # 热力图上的 Vpp 文字标注

        # 信号预处理滤波器 - 抑制电机驱动噪声
        self.signal_filter = SignalFilter(fs_hz=1e6)
        self.signal_filter.filter_enabled = True
        self.background_signal: Optional[np.ndarray] = None  # 背景参考信号

        self.serial_cfg = {"x_port": "COM20", "y_port": "COM21", "z_port": "COM22",
                           "baudrate": 19200, "parity": "even", "stopbits": 1, "databits": 8}
        self.acq_worker = None
        self.scan_worker = None
        self.traj_worker = None

        preset_path = os.path.join(os.path.expanduser("~"), ".rigol_bmode", "presets.json")
        self.presets = PresetStore(preset_path)

        # Apply global theme first (so pyqtgraph inherits background)
        self._apply_theme()

        # Build UI
        root = QWidget()
        self.setCentralWidget(root)
        outer = QVBoxLayout(root)
        outer.setContentsMargins(10, 10, 10, 10)
        outer.setSpacing(8)

        # ── Top header bar ──────────────────────────────────────────
        header = self._build_header()
        outer.addWidget(header)

        # ── Main splitter ───────────────────────────────────────────
        splitter = QSplitter(Qt.Horizontal)
        splitter.setHandleWidth(6)
        outer.addWidget(splitter, 1)

        left_panel = self._build_left_panel()
        right_panel = self._build_right_panel()

        splitter.addWidget(left_panel)
        splitter.addWidget(right_panel)
        splitter.setSizes([330, 1370])  # 左侧控制区域宽度
        splitter.setStyleSheet(f"""
            QSplitter::handle {{
                background: {BORDER};
                border-radius: 3px;
                margin: 40px 1px;
            }}
            QSplitter::handle:hover {{
                background: {ACCENT};
            }}
        """)

        # ── Bottom status bar ───────────────────────────────────────
        status_bar = self._build_status_bar()
        outer.addWidget(status_bar)

        # Timers
        self.timer = QTimer(self)
        self.timer.setInterval(1000)
        self.timer.timeout.connect(self.refresh_info)

        self.disk_timer = QTimer(self)
        self.disk_timer.setInterval(3000)
        self.disk_timer.timeout.connect(self.refresh_disk)

        self._setup_shortcuts()
        self.refresh_status()
        self.refresh_disk()

        # 初始化透射成像模式UI
        self._init_transmission_mode()

    def _init_transmission_mode(self):
        """初始化透射成像模式（默认模式）"""
        # 设置UI控件可见性
        self.bmode_card.setTitle("透射成像")
        self.slider_contrast.setVisible(False)
        self.slider_dr.setVisible(False)
        self.slider_time_start.setVisible(True)
        self.slider_time_end.setVisible(True)
        self.vpp_norm_lbl.setVisible(True)
        self.vpp_norm_edit.setVisible(True)
        self.vpp_norm_unit.setVisible(True)
        self.btn_show_vpp_labels.setVisible(True)
        # 更新时间范围
        self._update_transmission_time_range()

    # ════════════════════════════════════════════════════════════════
    #  UI Builders
    # ════════════════════════════════════════════════════════════════

    def _build_header(self) -> QWidget:
        bar = QWidget()
        bar.setFixedHeight(60)  # 增加高度
        bar.setObjectName("headerBar")
        lay = QHBoxLayout(bar)
        lay.setContentsMargins(20, 0, 20, 0)  # 增加左右边距
        lay.setSpacing(16)

        # Title - 增强字体层级
        title = QLabel("SONIC  SCAN")
        title.setStyleSheet(f"""
            color: {TEXT};
            font-size: 18px;
            font-weight: 700;
            letter-spacing: 4px;
        """)
        sub = QLabel("超声扫描成像系统")
        sub.setStyleSheet(f"color:{MUTED2}; font-size:12px; letter-spacing:1.5px; background:transparent;")
        title_col = QVBoxLayout()
        title_col.setSpacing(2)
        title_col.addWidget(title)
        title_col.addWidget(sub)

        # Status chips in header - 优化样式
        self.lamp_scope = StatusLamp("#374151")
        self.lbl_scope = QLabel("示波器")
        self.lbl_scope.setStyleSheet(f"color:{MUTED2}; font-size:12px; font-weight:500; background:transparent;")

        self.lamp_stage = StatusLamp("#374151")
        self.lbl_stage = QLabel("三轴平台")
        self.lbl_stage.setStyleSheet(f"color:{MUTED2}; font-size:12px; font-weight:500; background:transparent;")

        self.lbl_banner = QLabel("系统就绪")
        self.lbl_banner.setStyleSheet(f"""
            color: {OK};
            font-size: 13px;
            font-weight: 700;
            padding: 6px 18px;
            background: rgba(16,185,129,0.15);
            border: 1.5px solid rgba(16,185,129,0.4);
            border-radius: 14px;
        """)

        scope_row = QHBoxLayout()
        scope_row.setSpacing(6)
        scope_row.addWidget(self.lamp_scope)
        scope_row.addWidget(self.lbl_scope)

        stage_row = QHBoxLayout()
        stage_row.setSpacing(6)
        stage_row.addWidget(self.lamp_stage)
        stage_row.addWidget(self.lbl_stage)

        lay.addLayout(title_col)
        lay.addStretch(1)
        lay.addLayout(scope_row)
        lay.addSpacing(20)
        lay.addLayout(stage_row)
        lay.addSpacing(24)
        lay.addWidget(self.lbl_banner)

        bar.setStyleSheet(f"""
            #headerBar {{
                background: qlineargradient(x1:0, y1:0, x2:1, y2:0,
                    stop:0 {PANEL}, stop:0.5 {PANEL2}, stop:1 {PANEL});
                border: 1px solid {BORDER};
                border-radius: 12px;
            }}
            #headerBar QLabel {{
                background: transparent;
            }}
        """)
        return bar

    def _build_left_panel(self) -> QWidget:
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        scroll.setObjectName("leftScroll")

        container = QWidget()
        container.setObjectName("leftContainer")
        left = QVBoxLayout(container)
        left.setContentsMargins(4, 6, 4, 6)
        left.setSpacing(8)
        scroll.setWidget(container)

        self.log = LogView()

        # ── Section: Connection & Save ──
        conn_box = CollapsibleBox("🔌 连接与保存", expanded=True)
        conn_layout = QVBoxLayout()
        conn_layout.setSpacing(8)  # 优化：缩小间距 10→8

        # Row 0: Save path
        path_row = QHBoxLayout()
        path_row.setSpacing(6)  # 优化：缩小间距 8→6
        path_lbl = QLabel("保存路径")
        path_lbl.setFixedWidth(54)
        path_lbl.setStyleSheet(f"color:{MUTED2}; font-size:12px; font-weight:500; background:transparent;")
        self.save_path = QLineEdit(r"D:\rigol_data")
        self.save_path.setPlaceholderText("数据保存路径…")
        self.btn_browse = QPushButton("选择")
        self.btn_browse.setFixedWidth(52)
        self.btn_browse.clicked.connect(self.on_browse)
        path_row.addWidget(path_lbl)
        path_row.addWidget(self.save_path, 1)
        path_row.addWidget(self.btn_browse)
        conn_layout.addLayout(path_row)

        # Row 1: VISA address
        visa_row = QHBoxLayout()
        visa_row.setSpacing(8)
        visa_lbl = QLabel("VISA 地址")
        visa_lbl.setFixedWidth(58)
        visa_lbl.setStyleSheet(f"color:{MUTED2}; font-size:12px; font-weight:500; background:transparent;")
        self.visa_addr = QLineEdit("USB0::0x1AB1::0x0515::MS5A263402210::INSTR")
        self.visa_addr.setPlaceholderText("VISA 仪器地址")
        visa_row.addWidget(visa_lbl)
        visa_row.addWidget(self.visa_addr, 1)
        conn_layout.addLayout(visa_row)

        # Row 2: Connect buttons
        btn_row = QHBoxLayout()
        btn_row.setSpacing(8)
        self.btn_scope = QPushButton("⚡ 连接示波器")
        self.btn_scope.setProperty("role", "primary")
        self.btn_scope.setMinimumHeight(42)  # 优化：统一主按钮高度
        self.btn_scope.clicked.connect(self.on_toggle_scope)

        self.btn_serial_settings = QPushButton("⚙ 串口设置")
        self.btn_serial_settings.setMinimumHeight(42)
        self.btn_serial_settings.clicked.connect(self.on_serial_settings)

        self.btn_stage = QPushButton("⚡ 连接三轴")
        self.btn_stage.setProperty("role", "primary")
        self.btn_stage.setMinimumHeight(42)
        self.btn_stage.clicked.connect(self.on_toggle_serial)

        btn_row.addWidget(self.btn_scope, 2)
        btn_row.addWidget(self.btn_serial_settings, 1)
        btn_row.addWidget(self.btn_stage, 2)
        conn_layout.addLayout(btn_row)

        # Stub out preset objects so existing methods don't crash
        self.visa_preset = QComboBox(); self.visa_preset.hide()
        self.btn_save_visa_preset = QToolButton(); self.btn_save_visa_preset.hide()
        self.serial_preset = QComboBox(); self.serial_preset.hide()
        self.btn_save_serial_preset = QToolButton(); self.btn_save_serial_preset.hide()

        conn_box.setContentLayout(conn_layout)
        left.addWidget(conn_box)
        left.addWidget(self._make_divider())

        # ── Section: Acquisition ──
        acq_box = CollapsibleBox("📊 采集控制", expanded=True)
        acq_layout = QVBoxLayout()
        acq_layout.setSpacing(8)

        # Row 1: 通道 + 平均 + 点数
        acq_row1 = QHBoxLayout()
        acq_row1.setSpacing(8)

        ch_lbl = QLabel("通道")
        ch_lbl.setStyleSheet(f"color:{MUTED2}; font-size:12px; font-weight:500; background:transparent;")
        self.scope_channel = QComboBox()
        self.scope_channel.addItems(["1", "2", "3", "4"])
        self.scope_channel.setFixedWidth(52)
        self.scope_channel.setFixedHeight(28)

        avg_lbl = QLabel("平均")
        avg_lbl.setStyleSheet(f"color:{MUTED2}; font-size:12px; font-weight:500; background:transparent;")
        self.avg_combo = QComboBox()
        self.avg_combo.addItems(["无", "2次", "4次", "8次", "16次", "32次", "64次"])
        self.avg_combo.setCurrentIndex(0)
        self.avg_combo.setFixedWidth(62)
        self.avg_combo.setFixedHeight(28)
        self.avg_combo.currentTextChanged.connect(self._on_average_changed)

        pts_lbl = QLabel("点数")
        pts_lbl.setStyleSheet(f"color:{MUTED2}; font-size:12px; font-weight:500; background:transparent;")
        self.acq_points_edit = QLineEdit("1")
        self.acq_points_edit.setFixedWidth(44)
        self.acq_points_edit.setFixedHeight(28)
        self.acq_points_edit.setPlaceholderText("K")
        self.acq_points_edit.setToolTip(">1K 时自动切换 STOP 模式深度采集")
        pts_unit_lbl = QLabel("K")
        pts_unit_lbl.setStyleSheet(f"color:{MUTED}; font-size:11px; background:transparent;")

        acq_row1.addWidget(ch_lbl)
        acq_row1.addWidget(self.scope_channel)
        acq_row1.addStretch(1)
        acq_row1.addWidget(avg_lbl)
        acq_row1.addWidget(self.avg_combo)
        acq_row1.addStretch(1)
        acq_row1.addWidget(pts_lbl)
        acq_row1.addWidget(self.acq_points_edit)
        acq_row1.addWidget(pts_unit_lbl)
        acq_layout.addLayout(acq_row1)

        # Row 2: 单次采集 + 保存
        acq_row2 = QHBoxLayout()
        acq_row2.setSpacing(8)

        self.btn_snapshot = QPushButton("▶  单次采集")
        self.btn_snapshot.setProperty("role", "primary")
        self.btn_snapshot.setFixedHeight(38)
        self.btn_snapshot.setFixedWidth(100)
        self.btn_snapshot.clicked.connect(self.on_snapshot_acquire)

        self.btn_save_wave = QPushButton("保存波形")
        self.btn_save_wave.setFixedHeight(38)
        self.btn_save_wave.setFixedWidth(110)
        self.btn_save_wave.clicked.connect(self.on_save_snapshot)
        self.btn_save_wave.setEnabled(False)

        acq_row2.addStretch(1)
        acq_row2.addWidget(self.btn_snapshot)
        acq_row2.addWidget(self.btn_save_wave)
        acq_row2.addStretch(1)
        acq_layout.addLayout(acq_row2)

        # Hidden elements for compatibility
        self.btn_export_wave = QPushButton("↓  导出波形")
        self.btn_export_wave.setVisible(False)
        self.btn_export_wave.clicked.connect(self.on_export_wave)
        
        self.points_slider = QSlider(Qt.Horizontal)
        self.points_slider.setMinimum(1000)
        self.points_slider.setMaximum(100000)
        self.points_slider.setValue(10000)
        self.points_slider.setVisible(False)
        
        self.points_edit = QLineEdit("1000")
        self.points_edit.setVisible(False)
        
        self.auto_toggle = QPushButton("◉  AUTO 连续采集")
        self.auto_toggle.setCheckable(True)
        self.auto_toggle.setProperty("role", "primary")
        self.auto_toggle.setVisible(False)
        self.auto_toggle.toggled.connect(self.on_auto_toggled)

        self.auto_progress = QProgressBar()
        self.auto_progress.setRange(0, 0)
        self.auto_progress.setVisible(False)
        self.auto_progress.setFixedHeight(3)
        self.auto_progress.setTextVisible(False)

        acq_box.setContentLayout(acq_layout)
        left.addWidget(acq_box)
        left.addWidget(self._make_divider())

        # ── Section: Motion & Scan ──
        motion_box = CollapsibleBox("🎯 位移与扫描", expanded=True)
        motion_layout = QVBoxLayout()
        motion_layout.setSpacing(8)  # 优化：缩小间距 10→8


        # 初始化系统按钮行（参考 MATLAB initBtn）
        init_row = QHBoxLayout()
        init_row.setSpacing(8)
        self.btn_init_system = QPushButton('⚙ 初始化系统')
        self.btn_init_system.setProperty('role', 'primary')
        self.btn_init_system.setMinimumHeight(42)
        self.btn_init_system.setFixedWidth(115)
        self.btn_init_system.setCheckable(True)
        self.btn_init_system.setEnabled(False)
        self.btn_init_system.clicked.connect(self.on_toggle_init_system)

        self.btn_clear_plot = QPushButton('🗑 清除图像')
        self.btn_clear_plot.setMinimumHeight(42)
        self.btn_clear_plot.setFixedWidth(115)
        self.btn_clear_plot.clicked.connect(self.on_clear_plot)

        init_row.addStretch(1)
        init_row.addWidget(self.btn_init_system)
        init_row.addWidget(self.btn_clear_plot)
        init_row.addStretch(1)
        motion_layout.addLayout(init_row)

        self.tabs = QTabWidget()
        self.tabs.setDocumentMode(True)

        # Tab: Continuous
        tab_cont = QWidget()
        gc = QGridLayout(tab_cont)
        gc.setHorizontalSpacing(6)  # 优化：缩小间距 8→6
        gc.setVerticalSpacing(8)  # 优化：缩小间距 10→8
        self.c_x = QLineEdit("0.0")
        self.c_y = QLineEdit("0.0")
        self.c_z = QLineEdit("0.0")
        self._add_mm_row(gc, 0, "X", self.c_x, "X")
        self._add_mm_row(gc, 1, "Y", self.c_y, "Y")
        self._add_mm_row(gc, 2, "Z", self.c_z, "Z")
        self.btn_cont_exec = QPushButton("▶ 开始")
        self.btn_cont_exec.setProperty("role", "primary")
        self.btn_cont_exec.setFixedHeight(42)
        self.btn_cont_stop = QPushButton("■ 停止")
        self.btn_cont_stop.setProperty("role", "danger")
        self.btn_cont_stop.setFixedHeight(42)
        self.btn_cont_exec.clicked.connect(self.on_continuous_move)
        self.btn_cont_stop.clicked.connect(self.on_stop_all)
        gc.addWidget(self.btn_cont_exec, 3, 0, 1, 2)
        gc.addWidget(self.btn_cont_stop, 3, 2, 1, 2)
        gc.setRowMinimumHeight(3, 38)

        # Tab: Interval
        tab_int = QWidget()
        gi = QGridLayout(tab_int)
        gi.setHorizontalSpacing(6)  # 优化：缩小间距 8→6
        gi.setVerticalSpacing(6)  # 优化：缩小间距 8→6
        self.i_x = QLineEdit("0.0")
        self.i_y = QLineEdit("0.0")
        self.i_z = QLineEdit("0.0")
        self._add_mm_row(gi, 0, "X", self.i_x, "X")
        self._add_mm_row(gi, 1, "Y", self.i_y, "Y")
        self._add_mm_row(gi, 2, "Z", self.i_z, "Z")
        self.interval_mm = QLineEdit("0.1")
        self.pre_delay = QLineEdit("0.2")  # 优化：从0.5s改为0.2s，减少采集前等待
        gi.addWidget(self._field_row("间隔", self.interval_mm, "mm"), 3, 0, 1, 2)
        gi.addWidget(self._field_row("等待", self.pre_delay, "s"), 3, 2, 1, 2)
        self.btn_int_exec = QPushButton("▶ 开始")
        self.btn_int_exec.setProperty("role", "primary")
        self.btn_int_exec.setFixedHeight(42)
        self.btn_int_stop = QPushButton("■ 停止")
        self.btn_int_stop.setProperty("role", "danger")
        self.btn_int_stop.setFixedHeight(42)
        self.btn_int_exec.clicked.connect(self.on_interval_scan)
        self.btn_int_stop.clicked.connect(self.on_stop_all)
        gi.addWidget(self.btn_int_exec, 4, 0, 1, 2)
        gi.addWidget(self.btn_int_stop, 4, 2, 1, 2)
        gi.setRowMinimumHeight(4, 38)

        # Tab: Trajectory
        tab_traj = QWidget()
        gt = QGridLayout(tab_traj)
        gt.setHorizontalSpacing(6)  # 优化：缩小间距 8→6
        gt.setVerticalSpacing(6)  # 优化：缩小间距 8→6
        
        # 轴选择
        axis_lbl = QLabel("行程轴")
        axis_lbl.setStyleSheet(f"color:{MUTED2}; font-size:11px; background:transparent;")
        self.t_axis_span = QComboBox()
        self.t_axis_span.addItems(["X", "Y", "Z"])
        self.t_axis_span.setFixedWidth(50)

        line_axis_lbl = QLabel("行数轴")
        line_axis_lbl.setStyleSheet(f"color:{MUTED2}; font-size:11px; background:transparent;")
        self.t_axis_lines = QComboBox()
        self.t_axis_lines.addItems(["X", "Y", "Z"])
        self.t_axis_lines.setCurrentIndex(1)  # 默认 Y
        self.t_axis_lines.setFixedWidth(50)

        # 第一行：轴选择
        axis_row = QHBoxLayout()
        axis_row.setSpacing(4)
        axis_row.addWidget(axis_lbl)
        axis_row.addWidget(self.t_axis_span)
        axis_row.addSpacing(8)
        axis_row.addWidget(line_axis_lbl)
        axis_row.addWidget(self.t_axis_lines)
        axis_row.addStretch(1)
        gt.addLayout(axis_row, 0, 0, 1, 4)
        
        self.t_xspan = QLineEdit("10.0")
        self.t_xstep = QLineEdit("1.0")
        self.t_ystep = QLineEdit("1.0")
        self.t_ylines = QLineEdit("10")
        self.t_start = QComboBox()
        self.t_start.addItems(["从当前位置开始", "从 (0,0) 开始"])
        self.t_save = QComboBox()
        self.t_save.addItems(["每点保存 Excel", "不保存 Excel"])
        gt.addWidget(self._field_row("行程", self.t_xspan, "mm"), 1, 0, 1, 2)
        gt.addWidget(self._field_row("步距", self.t_xstep, "mm"), 1, 2, 1, 2)
        gt.addWidget(self._field_row("行步距", self.t_ystep, "mm"), 2, 0, 1, 2)
        gt.addWidget(self._field_row("行数", self.t_ylines, ""), 2, 2, 1, 2)
        
        # ── 左侧：起点和保存控件（紧凑布局）──
        left_options = QWidget()
        left_layout = QVBoxLayout(left_options)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(6)  # 优化：缩小间距 8→6
        
        # 起点选择
        start_row = QHBoxLayout()
        start_row.setSpacing(5)  # 优化：缩小间距 6→5
        start_lbl = QLabel("起点")
        start_lbl.setStyleSheet(f"color:{MUTED2}; font-size:12px; font-weight:500; background:transparent;")
        start_lbl.setFixedWidth(28)
        self.t_start.setFixedWidth(110)
        start_row.addWidget(start_lbl)
        start_row.addWidget(self.t_start)
        start_row.addStretch(1)
        
        # 保存选择
        save_row = QHBoxLayout()
        save_row.setSpacing(5)  # 优化：缩小间距 6→5
        save_lbl = QLabel("保存")
        save_lbl.setStyleSheet(f"color:{MUTED2}; font-size:12px; font-weight:500; background:transparent;")
        save_lbl.setFixedWidth(28)
        self.t_save.setFixedWidth(110)
        save_row.addWidget(save_lbl)
        save_row.addWidget(self.t_save)
        save_row.addStretch(1)
        
        left_layout.addLayout(start_row)
        left_layout.addLayout(save_row)
        
        # ── 右侧：扫描预览卡片 ──
        preview_card = QWidget()
        preview_card.setStyleSheet(f"""
            QWidget {{
                background: rgba(59,130,246,0.08);
                border: 1px solid rgba(59,130,246,0.25);
                border-radius: 8px;
            }}
        """)
        preview_layout = QVBoxLayout(preview_card)
        preview_layout.setContentsMargins(10, 8, 10, 8)  # 优化：缩小内边距 12,10→10,8
        preview_layout.setSpacing(5)  # 优化：缩小间距 6→5

        preview_title = QLabel("📊 扫描预览")
        preview_title.setStyleSheet(f"color:{ACCENT2}; font-size:13px; font-weight:700; background:transparent;")

        self.preview_points = QLabel("总点数: 100")
        self.preview_time = QLabel("预计时间: 50.0 秒 (0.8 分钟)")
        self.preview_area = QLabel("扫描面积: 90.00 mm²")

        for lbl in [self.preview_points, self.preview_time, self.preview_area]:
            lbl.setStyleSheet(f"color:{TEXT}; font-size:12px; background:transparent; font-weight:500;")

        preview_layout.addWidget(preview_title)
        preview_layout.addWidget(self.preview_points)
        preview_layout.addWidget(self.preview_time)
        preview_layout.addWidget(self.preview_area)
        
        # ── 并列布局：左侧控件 + 右侧预览 ──
        gt.addWidget(left_options, 3, 0, 2, 2)
        gt.addWidget(preview_card, 3, 2, 2, 2)
        
        # 连接信号以实时更新预览
        for widget in [self.t_xspan, self.t_xstep, self.t_ystep, self.t_ylines]:
            widget.textChanged.connect(self._update_trajectory_preview)
        
        # 初始更新
        self._update_trajectory_preview()
        
        # ── 底部：开始和停止按钮 ──
        self.btn_traj_exec = QPushButton("▶ 开始")
        self.btn_traj_exec.setProperty("role", "primary")
        self.btn_traj_exec.setFixedHeight(42)
        self.btn_traj_stop = QPushButton("■ 停止")
        self.btn_traj_stop.setProperty("role", "danger")
        self.btn_traj_stop.setFixedHeight(42)
        self.btn_traj_exec.clicked.connect(self.on_trajectory_scan)
        self.btn_traj_stop.clicked.connect(self.on_stop_all)
        gt.addWidget(self.btn_traj_exec, 5, 0, 1, 2)
        gt.addWidget(self.btn_traj_stop, 5, 2, 1, 2)
        gt.setRowMinimumHeight(5, 38)

        self.tabs.addTab(tab_cont, "连续位移")
        self.tabs.addTab(tab_int, "间隔位移")
        self.tabs.addTab(tab_traj, "轨迹位移")

        motion_layout.addWidget(self.tabs)
        motion_box.setContentLayout(motion_layout)
        left.addWidget(motion_box)
        left.addWidget(self._make_divider())

        # ── Section: Log ──
        log_box = CollapsibleBox("📝 运行日志", expanded=True)
        log_layout = QVBoxLayout()
        log_layout.setSpacing(6)
        act_row = QHBoxLayout()
        act_row.setSpacing(6)
        btn_clear = QPushButton("清空")
        btn_clear.setFixedHeight(30)
        btn_clear.clicked.connect(lambda: self.log.setHtml(""))
        btn_export_log = QPushButton("导出日志")
        btn_export_log.setFixedHeight(30)
        btn_export_log.clicked.connect(self.on_export_log)
        act_row.addWidget(btn_clear)
        act_row.addWidget(btn_export_log)
        act_row.addStretch(1)
        log_layout.addLayout(act_row)
        self.log.setMinimumHeight(240)
        log_layout.addWidget(self.log, 1)
        log_box.setContentLayout(log_layout)
        left.addWidget(log_box, 3)
        left.addStretch(1)

        return scroll

    def _build_right_panel(self) -> QWidget:
        container = QWidget()
        container.setObjectName("rightPanel")
        right = QVBoxLayout(container)
        right.setContentsMargins(0, 0, 0, 0)
        right.setSpacing(8)

        # ── Waveform panel ──────────────────────────────────────────
        wave_card = QGroupBox("实时波形")
        wave_card.setObjectName("waveCard")
        wave_card.setFixedHeight(280)
        wave_l = QVBoxLayout(wave_card)
        wave_l.setSpacing(2)
        wave_l.setContentsMargins(8, 8, 8, 4)

        self.wave_plot = pg.PlotWidget()
        self.wave_plot.showGrid(x=True, y=True, alpha=0.15)  # 优化：增强网格可见度
        self.wave_plot.setLabel("bottom", "时间", units="µs")
        self.wave_plot.setLabel("left", "电压", units="V")
        self.wave_plot.setMouseEnabled(x=True, y=True)
        self.wave_plot.setDownsampling(auto=True, mode="peak")
        self.wave_plot.setClipToView(True)
        self.wave_plot.scene().sigMouseMoved.connect(self._on_wave_mouse)
        self.wave_curve = self.wave_plot.plot([], [], pen=pg.mkPen(ACCENT, width=2))
        
        # 优化：添加十字光标
        self.crosshair_v = pg.InfiniteLine(angle=90, movable=False, 
                                           pen=pg.mkPen(INFO, width=1, style=Qt.DashLine))
        self.crosshair_h = pg.InfiniteLine(angle=0, movable=False,
                                           pen=pg.mkPen(INFO, width=1, style=Qt.DashLine))
        self.wave_plot.addItem(self.crosshair_v, ignoreBounds=True)
        self.wave_plot.addItem(self.crosshair_h, ignoreBounds=True)

        try:
            for ax in (self.wave_plot.getAxis("bottom"), self.wave_plot.getAxis("left")):
                ax.setStyle(tickFont=QFont("Consolas", 10), tickTextOffset=5)
                ax.setPen(pg.mkPen(BORDER_A, width=2))  # 优化：加粗坐标轴
                ax.setTextPen(pg.mkPen(MUTED2))
        except Exception:
            pass

        self.wave_plot.setFixedHeight(200)
        wave_l.addWidget(self.wave_plot)

        # Measurements row
        meas_row = QHBoxLayout()
        meas_row.setSpacing(4)
        meas_row.setContentsMargins(0, 2, 0, 16)

        self.btn_meas_peak = QPushButton("峰值 / Vpp")
        self.btn_meas_peak.setCheckable(True)
        self.btn_meas_peak.setFixedHeight(22)
        self.btn_meas_peak.clicked.connect(lambda: (self._set_meas_exclusive("peak"), self.on_meas_peak()))

        self.btn_meas_mean = QPushButton("均值 / RMS")
        self.btn_meas_mean.setCheckable(True)
        self.btn_meas_mean.setFixedHeight(22)
        self.btn_meas_mean.clicked.connect(lambda: (self._set_meas_exclusive("mean"), self.on_meas_mean()))

        self.btn_meas_freq = QPushButton("频率(估算)")
        self.btn_meas_freq.setCheckable(True)
        self.btn_meas_freq.setFixedHeight(22)
        self.btn_meas_freq.clicked.connect(lambda: (self._set_meas_exclusive("freq"), self.on_meas_freq()))

        self.lbl_meas = QLabel("—")
        self.lbl_meas.setStyleSheet(f"color:{ACCENT}; font-size:11px; font-weight:600; background:transparent;")

        self.meas_text = pg.TextItem(color=TEXT, anchor=(0, 0))
        try:
            self.wave_plot.addItem(self.meas_text)
            self.meas_text.setPos(0, 0)
        except Exception:
            pass

        # Cursor readout
        self.lbl_cursor = QLabel("x=— µs, y=— V")
        self.lbl_cursor.setStyleSheet(f"color:{MUTED}; font-size:10px; font-family:Consolas; background:transparent;")

        self.chk_spike_filter = QCheckBox("去尖峰")
        self.chk_spike_filter.setToolTip("启用中值滤波去除尖峰/脉冲噪声（不影响存储数据）")
        self.chk_spike_filter.setStyleSheet(f"color:{MUTED2}; font-size:11px; background:transparent;")

        self.spike_kernel_spin = QSpinBox()
        self.spike_kernel_spin.setRange(3, 21)
        self.spike_kernel_spin.setSingleStep(2)
        self.spike_kernel_spin.setValue(5)
        self.spike_kernel_spin.setToolTip("中值滤波窗口大小（奇数，越大去除越多）")
        self.spike_kernel_spin.setFixedWidth(44)
        self.spike_kernel_spin.setFixedHeight(22)
        self.spike_kernel_spin.setStyleSheet(
            f"QSpinBox {{ background:{BG}; color:{MUTED2}; border:1px solid {BORDER_A};"
            f" border-radius:3px; font-size:11px; padding:1px 2px; }}"
            f"QSpinBox::up-button, QSpinBox::down-button {{ width:14px; }}"
        )

        meas_row.addWidget(self.btn_meas_peak)
        meas_row.addWidget(self.btn_meas_mean)
        meas_row.addWidget(self.btn_meas_freq)
        meas_row.addSpacing(8)
        meas_row.addWidget(self.chk_spike_filter)
        meas_row.addWidget(self.spike_kernel_spin)
        meas_row.addStretch(1)
        meas_row.addWidget(self.lbl_meas)
        meas_row.addSpacing(14)
        meas_row.addWidget(self.lbl_cursor)
        wave_l.addLayout(meas_row)

        # ── B-Mode panel ────────────────────────────────────────────
        self.bmode_card = QGroupBox("B 模式成像")
        self.bmode_card.setObjectName("bmodeCard")
        bm = QVBoxLayout(self.bmode_card)
        bm.setSpacing(8)

        # Controls row - 直接添加所有滑块，通过 setVisible 控制显示
        ctrl_row = QHBoxLayout()
        ctrl_row.setSpacing(6)

        # 成像模式选择
        mode_lbl = QLabel("模式")
        mode_lbl.setStyleSheet(f"color:{MUTED2}; font-size:11px; background:transparent;")
        self.imaging_mode_combo = QComboBox()
        self.imaging_mode_combo.addItems(["B 模式", "透射成像"])
        self.imaging_mode_combo.setFixedWidth(100)
        self.imaging_mode_combo.setCurrentText("透射成像")  # 默认透射成像
        self.imaging_mode_combo.currentTextChanged.connect(self._on_imaging_mode_changed)

        cmap_lbl = QLabel("伪彩")
        cmap_lbl.setStyleSheet(f"color:{MUTED2}; font-size:11px; background:transparent;")
        self.cmap = QComboBox()
        self.cmap.addItems(["彩虹", "灰度", "热金属", "蓝黄"])
        self.cmap.setFixedWidth(100)
        self.cmap.currentTextChanged.connect(self._apply_cmap)

        # B 模式控制器
        self.slider_contrast = SliderRow("对比度", 50, 200, 140, "×")
        self.slider_contrast.slider.valueChanged.connect(self._on_bmode_adjust)

        self.slider_dr = SliderRow("DR", 20, 80, 50, "dB")
        self.slider_dr.slider.valueChanged.connect(self._on_bmode_adjust)

        # 透射成像控制器
        self.slider_time_start = SliderRow("起点", 0, 100, 0, "µs")
        self.slider_time_start.slider.valueChanged.connect(self._on_transmission_adjust)
        self.slider_time_start.setVisible(False)

        self.slider_time_end = SliderRow("终点", 0, 100, 10, "µs")
        self.slider_time_end.slider.valueChanged.connect(self._on_transmission_adjust)
        self.slider_time_end.setVisible(False)

        # legacy compat attributes
        self.lbl_contrast = QLabel("1.40×")
        self.lbl_contrast.setStyleSheet("background:transparent;")
        self.lbl_dr = QLabel("50 dB")
        self.lbl_dr.setStyleSheet("background:transparent;")

        ctrl_row.addWidget(mode_lbl, 0)
        ctrl_row.addWidget(self.imaging_mode_combo, 0)
        ctrl_row.addSpacing(8)
        ctrl_row.addWidget(cmap_lbl, 0)
        ctrl_row.addWidget(self.cmap, 0)
        ctrl_row.addSpacing(8)
        ctrl_row.addWidget(self.slider_contrast, 2)
        ctrl_row.addWidget(self.slider_dr, 2)
        ctrl_row.addWidget(self.slider_time_start, 2)
        ctrl_row.addWidget(self.slider_time_end, 2)

        # 归一化最大值（透射成像专用）
        self.vpp_norm_lbl = QLabel("最大值")
        self.vpp_norm_lbl.setStyleSheet(f"color:{MUTED2}; font-size:11px; font-weight:500; background:transparent;")
        self.vpp_norm_lbl.setVisible(False)
        self.vpp_norm_edit = QLineEdit("1.0")
        self.vpp_norm_edit.setFixedWidth(54)
        self.vpp_norm_edit.setToolTip("归一化上限（V）：Vpp 超过此值时颜色饱和，留空则自动取最大值；回车后立即更新热力图")
        self.vpp_norm_edit.editingFinished.connect(self._on_vpp_norm_changed)
        self.vpp_norm_edit.setVisible(False)
        self.vpp_norm_unit = QLabel("V")
        self.vpp_norm_unit.setStyleSheet(f"color:{MUTED}; font-size:11px; background:transparent;")
        self.vpp_norm_unit.setVisible(False)
        ctrl_row.addSpacing(12)
        ctrl_row.addWidget(self.vpp_norm_lbl)
        ctrl_row.addSpacing(4)
        ctrl_row.addWidget(self.vpp_norm_edit)
        ctrl_row.addWidget(self.vpp_norm_unit)
        ctrl_row.addSpacing(12)

        self.btn_show_vpp_labels = QPushButton("显示 Vpp 数值")
        self.btn_show_vpp_labels.setCheckable(True)
        self.btn_show_vpp_labels.setVisible(False)
        self.btn_show_vpp_labels.toggled.connect(self._on_toggle_vpp_labels)
        ctrl_row.addWidget(self.btn_show_vpp_labels)

        ctrl_row.addStretch(1)
        bm.addLayout(ctrl_row)

        # 用 PlotWidget + ImageItem 替代 ImageView，模仿 MATLAB imagesc
        self.bmode_plot = pg.PlotWidget()
        self.bmode_plot.setLabel("bottom", "横向位置 (mm)")
        self.bmode_plot.setLabel("left", "深度 (mm)")
        self.bmode_plot.invertY(True)
        self.bmode_plot.setAspectLocked(False)
        self.bmode_plot.getAxis('bottom').enableAutoSIPrefix(False)
        self.bmode_plot.getAxis('left').enableAutoSIPrefix(False)
        self.img_item = pg.ImageItem()
        self.bmode_plot.addItem(self.img_item)
        bm.addWidget(self.bmode_plot, 1)
        self._apply_cmap(self.cmap.currentText())

        # Vertical splitter between wave and bmode
        v_split = QSplitter(Qt.Vertical)
        v_split.setHandleWidth(6)
        v_split.addWidget(wave_card)
        v_split.addWidget(self.bmode_card)
        v_split.setSizes([320, 620])
        v_split.setStyleSheet(f"""
            QSplitter::handle {{
                background: {BORDER};
                border-radius: 3px;
                margin: 0px 40px;
            }}
            QSplitter::handle:hover {{ background: {ACCENT}; }}
        """)

        right.addWidget(v_split, 1)
        return container

    def _build_status_bar(self) -> QWidget:
        bar = QWidget()
        bar.setFixedHeight(42)
        bar.setObjectName("statusBar")
        lay = QHBoxLayout(bar)
        lay.setContentsMargins(12, 4, 12, 4)
        lay.setSpacing(8)

        self.chip_srate = InfoChip("⏱", "采样率: —")
        self.chip_mdepth = InfoChip("🧠", "存储深度: —")
        self.chip_pos = InfoChip("📍", "X=0.00  Y=0.00  Z=0.00 mm")
        self.chip_path = InfoChip("📁", "路径: —")
        self.chip_disk = InfoChip("💾", "剩余空间: —")

        lay.addWidget(self.chip_srate)
        lay.addWidget(self.chip_mdepth)
        lay.addWidget(self.chip_pos)
        lay.addStretch(1)
        lay.addWidget(self.chip_path)
        lay.addWidget(self.chip_disk)

        bar.setStyleSheet(f"""
            #statusBar {{
                background: {PANEL};
                border: 1px solid {BORDER};
                border-radius: 8px;
            }}
        """)
        return bar

    # ════════════════════════════════════════════════════════════════
    #  Widget Helpers
    # ════════════════════════════════════════════════════════════════

    def _make_divider(self) -> QFrame:
        line = QFrame()
        line.setFrameShape(QFrame.HLine)
        line.setFixedHeight(1)
        line.setStyleSheet(f"background: {BORDER}; border: none;")
        return line

    def _field_row(self, label: str, edit: QLineEdit, unit: str) -> QWidget:
        w = QWidget()
        h = QHBoxLayout(w)
        h.setContentsMargins(0, 0, 0, 0)
        h.setSpacing(4)
        lbl = QLabel(label)
        lbl.setStyleSheet(f"color:{MUTED2}; font-size:11px; background:transparent;")
        lbl.setFixedWidth(38)
        h.addWidget(lbl)
        h.addWidget(edit, 1)
        if unit:
            u = QLabel(unit)
            u.setStyleSheet(f"color:{MUTED}; font-size:10px; background:transparent;")
            h.addWidget(u)
        return w

    def _add_mm_row(self, grid: QGridLayout, row: int, label: str, edit: QLineEdit, axis: str):
        lbl = QLabel(f"{label} 目标")
        lbl.setFixedWidth(38)
        lbl.setStyleSheet(f"background:transparent;")
        grid.addWidget(lbl, row, 0)

        wrap = QWidget()
        h = QHBoxLayout(wrap)
        h.setContentsMargins(0, 0, 0, 0)
        h.setSpacing(3)
        edit.setAlignment(Qt.AlignRight)
        edit.setFixedWidth(58)
        h.addWidget(edit)
        unit = QLabel("mm")
        unit.setStyleSheet(f"color:{MUTED}; font-size:10px; background:transparent;")
        h.addWidget(unit)

        for txt, delta in [("−10", -10), ("−0.1", -0.1), ("+0.1", +0.1), ("+10", +10)]:
            btn = QToolButton()
            btn.setText(txt)
            btn.setFixedSize(38, 28)
            btn.clicked.connect(lambda _, e=edit, d=delta: self._nudge(e, d))
            h.addWidget(btn)

        grid.addWidget(wrap, row, 1, 1, 3)

    def _nudge(self, edit: QLineEdit, delta: float):
        v = _safe_float(edit.text(), 0.0) + float(delta)
        edit.setText(f"{v:.2f}")

    def _update_trajectory_preview(self):
        """实时更新轨迹扫描预览信息"""
        try:
            span = _safe_float(self.t_xspan.text(), 10.0)
            step = _safe_float(self.t_xstep.text(), 1.0)
            ystep = _safe_float(self.t_ystep.text(), 1.0)
            lines = int(_safe_float(self.t_ylines.text(), 10))
            
            # 防止除零错误
            if step <= 0:
                step = 0.1
            if ystep <= 0:
                ystep = 0.1
            if lines <= 0:
                lines = 1
            
            # 计算总点数
            points_per_line = int(span / step) + 1
            total_points = points_per_line * lines
            
            # 预计时间（假设每点采集时间为 0.5 秒）
            est_time_sec = total_points * 0.5
            est_time_min = est_time_sec / 60.0
            
            # 扫描面积
            area = span * (ystep * (lines - 1)) if lines > 1 else 0
            
            # 更新显示
            self.preview_points.setText(f"总点数: {total_points}")
            
            if est_time_min < 1:
                self.preview_time.setText(f"预计时间: {est_time_sec:.1f} 秒")
            else:
                self.preview_time.setText(f"预计时间: {est_time_sec:.1f} 秒 ({est_time_min:.1f} 分钟)")
            
            self.preview_area.setText(f"扫描面积: {area:.2f} mm²")
            
        except Exception as e:
            # 如果计算失败，显示默认值
            self.preview_points.setText("总点数: --")
            self.preview_time.setText("预计时间: --")
            self.preview_area.setText("扫描面积: --")

    # ════════════════════════════════════════════════════════════════
    #  Theme
    # ════════════════════════════════════════════════════════════════

    def _apply_theme(self):
        pg.setConfigOption("background", PANEL)
        pg.setConfigOption("foreground", TEXT)

        self.setStyleSheet(f"""
        /* ── Base ──────────────────────────────────── */
        QMainWindow, QWidget {{
            background: {BG};
            color: {TEXT};
            font-family: "Microsoft YaHei", "PingFang SC", sans-serif;
            font-size: 12px;
        }}

        /* ── ScrollArea ─────────────────────────────── */
        QScrollArea, QScrollArea > QWidget > QWidget {{
            background: transparent;
            border: none;
        }}
        QScrollBar:vertical {{
            background: {PANEL};
            width: 6px;
            border-radius: 3px;
        }}
        QScrollBar::handle:vertical {{
            background: {BORDER_A};
            border-radius: 3px;
            min-height: 24px;
        }}
        QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{
            height: 0px;
        }}

        /* ── Labels ─────────────────────────────────── */
        QLabel {{ color: {TEXT}; font-size: 12px; background: transparent; }}

        /* ── GroupBox ───────────────────────────────── */
        QGroupBox {{
            background: {PANEL};
            border: 1px solid {BORDER};
            border-radius: 10px;
            margin-top: 18px;
            padding-top: 6px;
        }}
        QGroupBox::title {{
            subcontrol-origin: margin;
            left: 14px;
            top: 2px;
            padding: 0 8px;
            color: {ACCENT2};
            font-weight: 700;
            font-size: 13px;
            letter-spacing: 0.5px;
        }}

        /* ── Inputs ─────────────────────────────────── */
        QLineEdit, QComboBox, QTextEdit {{
            background: {PANEL2};
            border: 1px solid {BORDER};
            border-radius: 6px;
            padding: 6px 10px;
            min-height: 32px;
            color: {TEXT};
            selection-background-color: {ACCENT};
        }}
        QLineEdit:focus, QComboBox:focus {{
            border-color: {ACCENT};
            background: {PANEL3};
        }}
        QLineEdit:hover, QComboBox:hover {{
            border-color: rgba(59,130,246,0.5);
        }}
        QLineEdit:disabled, QComboBox:disabled {{
            color: {MUTED};
            border-color: rgba(255,255,255,0.05);
            background: rgba(255,255,255,0.03);
        }}
        QComboBox::drop-down {{
            border: none;
            width: 24px;
        }}
        QComboBox::down-arrow {{
            image: none;
            border-left: 4px solid transparent;
            border-right: 4px solid transparent;
            border-top: 5px solid {MUTED2};
            margin-right: 6px;
        }}
        QComboBox QAbstractItemView {{
            background: {PANEL3};
            border: 1px solid {BORDER_A};
            border-radius: 6px;
            selection-background-color: rgba(59,130,246,0.3);
            outline: none;
        }}

        /* ── Buttons ─────────────────────────────────── */
        QPushButton {{
            background: {PANEL2};
            border: 1px solid {BORDER};
            border-radius: 7px;
            padding: 7px 14px;
            min-height: 34px;
            font-weight: 600;
            color: {TEXT};
        }}
        QPushButton:hover {{
            background: {PANEL3};
            border-color: rgba(59,130,246,0.6);
            color: #F8FAFC;
        }}
        QPushButton:pressed {{
            background: rgba(59,130,246,0.18);
            border-color: {ACCENT};
        }}
        QPushButton:disabled {{
            background: rgba(255,255,255,0.03);
            border-color: rgba(255,255,255,0.05);
            color: {MUTED};
        }}
        QPushButton[role="primary"] {{
            background: rgba(59,130,246,0.15);
            border-color: rgba(59,130,246,0.55);
            color: #93C5FD;
        }}
        QPushButton[role="primary"]:hover {{
            background: rgba(59,130,246,0.28);
            border-color: {ACCENT};
            color: #DBEAFE;
        }}
        QPushButton[role="primary"]:checked {{
            background: rgba(59,130,246,0.35);
            border-color: {ACCENT};
            color: #DBEAFE;
        }}
        QPushButton[role="connected"] {{
            background: rgba(34,197,94,0.15);
            border-color: rgba(34,197,94,0.55);
            color: #86EFAC;
        }}
        QPushButton[role="connected"]:hover {{
            background: rgba(34,197,94,0.25);
            border-color: {OK};
        }}
        QPushButton[role="danger"] {{
            background: rgba(239,68,68,0.12);
            border-color: rgba(239,68,68,0.45);
            color: #FCA5A5;
        }}
        QPushButton[role="danger"]:hover {{
            background: rgba(239,68,68,0.22);
            border-color: {BAD};
        }}
        QPushButton:checkable:checked {{
            background: rgba(59,130,246,0.25);
            border-color: {ACCENT};
            color: #DBEAFE;
        }}

        /* ── ToolButton ──────────────────────────────── */
        QToolButton {{
            background: {PANEL2};
            border: 1px solid {BORDER};
            border-radius: 6px;
            padding: 5px 8px;
            min-height: 30px;
            font-size: 11px;
            color: {MUTED2};
        }}
        QToolButton:hover {{
            background: {PANEL3};
            border-color: rgba(59,130,246,0.5);
            color: {TEXT};
        }}
        QToolButton:pressed {{
            background: rgba(59,130,246,0.18);
        }}
        QToolButton:checked {{
            background: {PANEL};
            border-color: {BORDER};
            color: {MUTED};
        }}

        /* ── Tabs ────────────────────────────────────── */
        QTabWidget::pane {{
            border: 1px solid {BORDER};
            border-radius: 8px;
            background: {PANEL};
            top: -1px;
        }}
        QTabBar {{
            background: transparent;
        }}
        QTabBar::tab {{
            background: transparent;
            padding: 8px 16px;
            margin-right: 2px;
            border-top-left-radius: 7px;
            border-top-right-radius: 7px;
            font-size: 12px;
            color: {MUTED2};
            min-height: 32px;
        }}
        QTabBar::tab:hover {{
            background: rgba(255,255,255,0.05);
            color: {TEXT};
        }}
        QTabBar::tab:selected {{
            background: rgba(59,130,246,0.18);
            border: 1px solid rgba(59,130,246,0.35);
            border-bottom: none;
            color: #93C5FD;
            font-weight: 700;
        }}

        /* ── Slider ──────────────────────────────────── */
        QSlider::groove:horizontal {{
            height: 5px;
            background: {PANEL3};
            border-radius: 2px;
        }}
        QSlider::sub-page:horizontal {{
            background: qlineargradient(x1:0,y1:0,x2:1,y2:0,
                stop:0 {ACCENT}, stop:1 {ACCENT2});
            border-radius: 2px;
        }}
        QSlider::handle:horizontal {{
            width: 15px;
            height: 15px;
            margin: -5px 0;
            border-radius: 7px;
            background: {ACCENT};
            border: 2px solid {BG};
        }}
        QSlider::handle:horizontal:hover {{
            background: #60A5FA;
        }}

        /* ── ProgressBar ─────────────────────────────── */
        QProgressBar {{
            background: {PANEL3};
            border: none;
            border-radius: 2px;
            height: 4px;
        }}
        QProgressBar::chunk {{
            background: qlineargradient(x1:0,y1:0,x2:1,y2:0,
                stop:0 {ACCENT}, stop:1 {ACCENT2});
            border-radius: 2px;
        }}

        /* ── CollapsibleBox toggles ──────────────────── */
        QToolButton[checkable="true"] {{
            background: {PANEL2};
            border: 1px solid {BORDER};
            border-radius: 7px;
            padding: 8px 12px;
            font-size: 12px;
            font-weight: 700;
            color: {TEXT};
            min-height: 36px;
            text-align: left;
        }}
        QToolButton[checkable="true"]:hover {{
            background: {PANEL3};
            border-color: rgba(59,130,246,0.4);
        }}

        /* ── Dialog ──────────────────────────────────── */
        QDialog {{
            background: {PANEL};
        }}
        QDialogButtonBox QPushButton {{
            min-width: 80px;
        }}

        /* ── TextEdit (log) ──────────────────────────── */
        QTextEdit {{
            background: {PANEL2};
            border: 1px solid {BORDER};
            border-radius: 7px;
            padding: 6px;
            font-family: "Consolas", "Courier New", monospace;
            font-size: 11px;
            line-height: 1.6;
        }}
        """)

        # pointer cursor on interactive widgets
        try:
            from PySide6.QtWidgets import QPushButton, QToolButton, QComboBox
            for w in self.findChildren((QPushButton, QToolButton, QComboBox)):
                w.setCursor(Qt.PointingHandCursor)
        except Exception:
            pass

    # ════════════════════════════════════════════════════════════════
    #  Shortcuts
    # ════════════════════════════════════════════════════════════════

    def _setup_shortcuts(self):
        a = QAction(self)
        a.setShortcut(QKeySequence("F5"))
        a.triggered.connect(self.on_snapshot_acquire)
        self.addAction(a)

        a = QAction(self)
        a.setShortcut(QKeySequence(Qt.Key_Space))
        a.triggered.connect(lambda: self.auto_toggle.setChecked(not self.auto_toggle.isChecked()))
        self.addAction(a)

        a = QAction(self)
        a.setShortcut(QKeySequence("Ctrl+S"))
        a.triggered.connect(self.on_export_wave)
        self.addAction(a)

    # ════════════════════════════════════════════════════════════════
    #  Presets
    # ════════════════════════════════════════════════════════════════

    def _refresh_visa_presets(self):
        self.visa_preset.blockSignals(True)
        self.visa_preset.clear()
        items = self.presets.data.get("visa_presets", [])
        if self.visa_addr.text().strip() and self.visa_addr.text().strip() not in items:
            items = [self.visa_addr.text().strip()] + items
        self.visa_preset.addItems(items)
        self.visa_preset.blockSignals(False)

    def _refresh_serial_presets(self):
        self.serial_preset.blockSignals(True)
        self.serial_preset.clear()
        items = self.presets.data.get("serial_presets", [])
        names = [it.get("name", f"preset_{i}") for i, it in enumerate(items)]
        self.serial_preset.addItems(names if names else ["(无)"])
        self.serial_preset.blockSignals(False)

    def on_save_visa_preset(self):
        v = self.visa_addr.text().strip()
        if not v:
            return
        items = self.presets.data.get("visa_presets", [])
        if v in items:
            items.remove(v)
        items.insert(0, v)
        self.presets.data["visa_presets"] = items[:12]
        self.presets.save()
        self._refresh_visa_presets()
        self.log.log("ok", "VISA 预设已保存")

    def on_save_serial_preset(self):
        name, ok = self._simple_text("预设名称", "输入串口配置名称（例如：默认/实验A）")
        if not ok or not name.strip():
            return
        items = self.presets.data.get("serial_presets", [])
        items = [it for it in items if it.get("name") != name.strip()]
        items.insert(0, {"name": name.strip(), "cfg": dict(self.serial_cfg)})
        self.presets.data["serial_presets"] = items[:12]
        self.presets.save()
        self._refresh_serial_presets()
        self.log.log("ok", "串口预设已保存")

    def _simple_text(self, title: str, label: str):
        d = QDialog(self)
        d.setWindowTitle(title)
        f = QFormLayout(d)
        e = QLineEdit()
        f.addRow(label, e)
        btn = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        btn.accepted.connect(d.accept)
        btn.rejected.connect(d.reject)
        f.addRow(btn)
        r = d.exec()
        return e.text(), (r == QDialog.Accepted)

    # ════════════════════════════════════════════════════════════════
    #  Connection
    # ════════════════════════════════════════════════════════════════

    def on_browse(self):
        folder = QFileDialog.getExistingDirectory(self, "选择保存目录", self.save_path.text())
        if folder:
            self.save_path.setText(folder)
            self.refresh_disk()

    def on_toggle_scope(self):
        try:
            if not self.scope.is_connected:
                # 检查是否已初始化
                if self.stage.is_initialized:
                    QMessageBox.warning(self, "提示", "请先断开系统初始化，再断开示波器")
                    return
                
                t0 = time.time()
                idn = self.scope.connect(self.visa_addr.text().strip())
                dt = time.time() - t0
                self.log.log("ok", f"示波器连接成功 ({dt:.2f}s): {idn}")
                self.btn_scope.setText("✔  已连接 · 点击断开")
                self.btn_scope.setProperty("role", "connected")
                self.btn_scope.setToolTip(idn)
                self._repolish(self.btn_scope)
                self.timer.start()
                self._update_init_button_state()
            else:
                # 检查是否已初始化
                if self.stage.is_initialized:
                    QMessageBox.warning(self, "提示", "请先断开系统初始化，再断开示波器")
                    return
                
                self.scope.disconnect()
                self.log.log("info", "示波器已断开")
                self.btn_scope.setText("⚡  连接示波器")
                self.btn_scope.setProperty("role", "primary")
                self.btn_scope.setToolTip("")
                self._repolish(self.btn_scope)
                self.timer.stop()
                self._update_init_button_state()
            self.refresh_status()
        except Exception as e:
            QMessageBox.critical(self, "示波器错误", str(e))
            self.log.log("error", str(e))

    def on_serial_settings(self):
        dlg = SerialSettingsDialog(self, self.serial_cfg)
        if dlg.exec():
            self.serial_cfg = dlg.get_config()
            self.log.log("ok", f"串口设置已更新: {self.serial_cfg}")

    def on_toggle_serial(self):
        try:
            if not self.stage.is_connected:
                cfg = self.serial_cfg
                ports = [cfg["x_port"], cfg["y_port"], cfg["z_port"]]
                t0 = time.time()
                self.stage.connect(ports, baudrate=int(cfg["baudrate"]),
                                   parity=cfg["parity"],
                                   stopbits=int(cfg["stopbits"]),
                                   databits=int(cfg["databits"]))
                dt = time.time() - t0
                self.log.log("ok", f"三轴串口连接成功 ({dt:.2f}s): {ports}")
                self.btn_stage.setText("✔  已连接 · 点击断开")
                self.btn_stage.setProperty("role", "connected")
                self.btn_stage.setToolTip(str(ports))
                self._repolish(self.btn_stage)
                self.disk_timer.start()
                self._update_init_button_state()
            else:
                # 检查是否已初始化
                if self.stage.is_initialized:
                    QMessageBox.warning(self, "提示", "请先断开系统初始化，再断开串口")
                    return
                
                self.stage.disconnect()
                self.log.log("info", "三轴串口已断开")
                self.btn_stage.setText("⚡  连接三轴")
                self.btn_stage.setProperty("role", "primary")
                self.btn_stage.setToolTip("")
                self._repolish(self.btn_stage)
                self.disk_timer.stop()
                self._update_init_button_state()
            self.refresh_status()
        except Exception as e:
            QMessageBox.critical(self, "串口错误", str(e))
            self.log.log("error", str(e))

    def on_toggle_init_system(self):
        """初始化/断开系统使能（参考 MATLAB initializeSystem 函数）"""
        try:
            if not self.stage.is_connected:
                QMessageBox.warning(self, "错误", "请先连接三轴串口！")
                self.btn_init_system.setChecked(False)
                return
            
            if not self.stage.is_initialized:
                # 执行初始化
                self.log.log("info", "正在初始化系统...")
                t0 = time.time()
                self.stage.initialize()
                dt = time.time() - t0
                self.log.log("ok", f"系统初始化完成 ({dt:.2f}s)")
                self.log.log("info", "当前位置已设为0点（初始参考点）")
                self.log.log("info", "提示：现在可以设置目标位置并执行位移")
                
                # 更新按钮状态
                self.btn_init_system.setText("✔  已初始化 · 点击断开")
                self.btn_init_system.setProperty("role", "connected")
                self._repolish(self.btn_init_system)
                
                # 启用位移按钮
                self.btn_cont_exec.setEnabled(True)
                self.btn_int_exec.setEnabled(True)
                self.btn_traj_exec.setEnabled(True)
            else:
                # 执行断开使能
                self.log.log("info", "正在断开系统使能...")
                t0 = time.time()
                self.stage.deinitialize()
                dt = time.time() - t0
                self.log.log("ok", f"断开使能完成 ({dt:.2f}s)")
                
                # 更新按钮状态
                self.btn_init_system.setText("⚙  初始化系统")
                self.btn_init_system.setProperty("role", "primary")
                self.btn_init_system.setChecked(False)  # 重要：取消选中状态
                self._repolish(self.btn_init_system)
                
                # 禁用位移按钮
                self.btn_cont_exec.setEnabled(False)
                self.btn_int_exec.setEnabled(False)
                self.btn_traj_exec.setEnabled(False)
                
                # 更新设备连接按钮状态
                self._update_device_buttons_state()
                
        except Exception as e:
            self.btn_init_system.setChecked(self.stage.is_initialized)
            QMessageBox.critical(self, "初始化错误", str(e))
            self.log.log("error", f"初始化失败: {str(e)}")
    
    def _update_init_button_state(self):
        """更新初始化按钮的启用状态"""
        # 只有当示波器和串口都连接后，才能启用初始化按钮
        can_init = self.scope.is_connected and self.stage.is_connected
        self.btn_init_system.setEnabled(can_init)
    
    def _update_device_buttons_state(self):
        """更新设备连接按钮的启用状态"""
        # 初始化后，禁用示波器和串口的断开功能（通过提示实现）
        # 这个方法预留，实际通过弹窗提示实现
        pass

    def on_clear_plot(self):
        """清除波形图和B模式图像"""
        try:
            # 清除波形图
            self.wave_curve.setData([], [])
            
            # 清除B模式图像
            self.img_item.clear()
            
            # 清除测量文本
            try:
                self.meas_text.setText("")
            except Exception:
                pass
            
            # 清除保存的波形数据
            if hasattr(self, "_last_wave"):
                delattr(self, "_last_wave")
            if hasattr(self, "_last_fs"):
                delattr(self, "_last_fs")
            if hasattr(self, "_last_time_s"):
                delattr(self, "_last_time_s")
            if hasattr(self, "_last_meta"):
                delattr(self, "_last_meta")
            if hasattr(self, "_last_channel"):
                delattr(self, "_last_channel")
            if hasattr(self, "_last_avg_text"):
                delattr(self, "_last_avg_text")
            
            # 禁用保存按钮
            self.btn_save_wave.setEnabled(False)
            
            # 取消测量按钮的选中状态
            self.btn_meas_peak.setChecked(False)
            self.btn_meas_mean.setChecked(False)
            self.btn_meas_freq.setChecked(False)
            
            self.log.log("info", "图像已清除")
            
        except Exception as e:
            self.log.log("error", f"清除图像失败: {e}")

    def _repolish(self, w):
        try:
            w.style().unpolish(w)
            w.style().polish(w)
        except Exception:
            pass

    # ════════════════════════════════════════════════════════════════
    #  Status Refresh
    # ════════════════════════════════════════════════════════════════

    def refresh_status(self):
        self.lamp_scope.set_color(OK if self.scope.is_connected else "#374151",
                                  glow=self.scope.is_connected)
        self.lamp_stage.set_color(OK if self.stage.is_connected else "#374151",
                                  glow=self.stage.is_connected)
        self.lbl_scope.setStyleSheet(
            f"color:{OK}; font-size:11px;" if self.scope.is_connected
            else f"color:{MUTED2}; font-size:11px;"
        )
        self.lbl_stage.setStyleSheet(
            f"color:{OK}; font-size:11px;" if self.stage.is_connected
            else f"color:{MUTED2}; font-size:11px;"
        )

        running = bool(self.acq_worker and self.acq_worker.is_running)
        if running:
            self.lbl_banner.setText("● 运行中")
            self.lbl_banner.setStyleSheet(f"""
                color:{ACCENT2}; font-size:12px; font-weight:700;
                padding:4px 14px;
                background:rgba(6,182,212,0.12);
                border:1px solid rgba(6,182,212,0.35);
                border-radius:12px;
            """)
        else:
            self.lbl_banner.setText("就绪")
            self.lbl_banner.setStyleSheet(f"""
                color:{OK}; font-size:12px; font-weight:700;
                padding:4px 14px;
                background:rgba(34,197,94,0.12);
                border:1px solid rgba(34,197,94,0.35);
                border-radius:12px;
            """)

        x = self.stage.current_mm.get("X", 0.0) if self.stage.is_connected else 0.0
        y = self.stage.current_mm.get("Y", 0.0) if self.stage.is_connected else 0.0
        z = self.stage.current_mm.get("Z", 0.0) if self.stage.is_connected else 0.0
        self.chip_pos.set_text(f"X={x:.2f}  Y={y:.2f}  Z={z:.2f} mm")
        self.chip_path.set_text(self.save_path.text().strip() or "—")

    def refresh_info(self):
        try:
            if self.scope.is_connected:
                try:
                    sr = self.scope.query(":ACQuire:SRATe?")
                    self.chip_srate.set_text(f"{float(sr)/1e6:.3f} MSa/s")
                except Exception:
                    pass
                try:
                    md = self.scope.query(":ACQuire:MDEPth?")
                    self.chip_mdepth.set_text(str(md))
                except Exception:
                    pass
        except Exception:
            pass
        try:
            self.refresh_status()
        except Exception:
            pass

    def refresh_disk(self):
        try:
            folder = self.save_path.text().strip() or "."
            os.makedirs(folder, exist_ok=True)
            _, _, free = shutil.disk_usage(folder)
            self.chip_disk.set_text(human_bytes(free))
        except Exception:
            self.chip_disk.set_text("—")

    # ════════════════════════════════════════════════════════════════
    #  Acquisition
    # ════════════════════════════════════════════════════════════════

    def on_auto_toggled(self, checked: bool):
        if checked:
            if not self.scope.is_connected:
                QMessageBox.warning(self, "提示", "请先连接示波器")
                self.auto_toggle.setChecked(False)
                return
            ch = int(self.scope_channel.currentText())
            pts = int(self.points_slider.value())

            # 设置平均模式（如果选择了）
            avg_text = self.avg_combo.currentText()
            if avg_text != "无":
                count = int(avg_text.replace("次", ""))
                self.scope.set_average_mode(count)
                self.log.log("info", f"AUTO 模式使用平均 {count} 次采集")

            self.acq_worker = AcquisitionWorker(self.scope, channel=ch, points=pts)
            self.acq_worker.new_frame.connect(self._on_auto_frame)
            self.acq_worker.log.connect(
                lambda m: self.log.log("warn", m) if "失败" in m else self.log.log("info", m)
            )
            self.acq_worker.start_continuous(0.5)
            self.auto_progress.setVisible(True)
            self.log.log("info", "AUTO 开始")
        else:
            if self.acq_worker and self.acq_worker.is_running:
                self.acq_worker.stop()
            self.auto_progress.setVisible(False)
            self.log.log("info", "AUTO 停止")
        self.refresh_status()

    def _apply_spike_filter(self, wave: np.ndarray) -> np.ndarray:
        """若去尖峰复选框已勾选，对显示波形应用中值滤波（不影响存储数据）"""
        if hasattr(self, 'chk_spike_filter') and self.chk_spike_filter.isChecked():
            kernel = self.spike_kernel_spin.value() if hasattr(self, 'spike_kernel_spin') else 5
            return self.signal_filter.remove_spikes(wave, kernel_size=kernel)
        return wave

    def _on_auto_frame(self, wave_v):
        self._last_wave = np.asarray(wave_v, dtype=np.float32)
        x = np.arange(self._last_wave.size, dtype=np.int32)
        display_wave = self._apply_spike_filter(self._last_wave)
        try:
            srate = float(self.scope.query(":ACQuire:SRATe?"))
            t_us = (x / srate) * 1e6
            self.wave_curve.setData(t_us, display_wave)
        except Exception:
            self.wave_curve.setData(x, display_wave)

    def _on_average_changed(self, text: str):
        """处理平均次数变化"""
        if not self.scope.is_connected:
            return
        try:
            if text == "无":
                self.scope.set_normal_mode()
                self.log.log("info", "采集模式: 普通")
            else:
                # 提取数字部分
                count = int(text.replace("次", ""))
                self.scope.set_average_mode(count)
                self.log.log("info", f"采集模式: 平均 {count} 次")
        except Exception as e:
            self.log.log("error", f"设置平均模式失败: {e}")

    def on_snapshot_acquire(self):
        if not self.scope.is_connected:
            QMessageBox.warning(self, "提示", "请先连接示波器")
            return
        try:
            ch = int(self.scope_channel.currentText())
            pts = int(float(self.acq_points_edit.text().strip()) * 1000)
            if pts <= 0:
                pts = 1000

            # 确保平均模式已设置
            avg_text = self.avg_combo.currentText()
            if avg_text != "无":
                count = int(avg_text.replace("次", ""))
                self.scope.set_average_mode(count)

            if pts > 1000:
                # STOP 模式：停止 -> 采集 -> 恢复 RUN
                wave_v, fs, n, time_s, meta = self.scope.acquire_stop_mode(channel=ch, points=pts)
            else:
                wave_v, fs, n, time_s, meta = self.scope.acquire_screen_norm(channel=ch, points=pts)
            self._last_wave = wave_v
            self._last_fs = fs
            self._last_time_s = time_s  # 保存时间轴
            self._last_meta = meta  # 保存元数据
            self._last_channel = ch  # 保存通道号
            self._last_avg_text = avg_text  # 保存平均设置
            
            t_us = time_s * 1e6
            self.wave_curve.setData(t_us, self._apply_spike_filter(wave_v))

            # 更新时间范围滑块的范围
            time_min_us = float(np.min(t_us))
            time_max_us = float(np.max(t_us))
            self._update_time_slider_range(time_min_us, time_max_us)

            # 启用保存按钮
            self.btn_save_wave.setEnabled(True)

            avg_info = f", 平均{avg_text.replace('次', '')}次" if avg_text != "无" else ""
            mode_info = " [STOP模式]" if pts > 1000 else ""
            self.log.log("ok", f"采集完成{mode_info}: Fs={fs/1e6:.3f} MSa/s, 请求点数={pts/1000:.1f}K, 返回点数={n/1000:.1f}K, 时间范围: {time_min_us:.2f}~{time_max_us:.2f}µs{avg_info}")
        except Exception as e:
            QMessageBox.critical(self, "采集错误", str(e))
            self.log.log("error", str(e))

    def on_export_wave(self):
        if not hasattr(self, "_last_wave"):
            self.log.log("warn", "暂无波形可导出（先采集一次）")
            return
        folder = self.save_path.text().strip()
        os.makedirs(folder, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S_%f")[:-3]
        csv_path = os.path.join(folder, f"wave_{ts}.csv")
        json_path = os.path.join(folder, f"wave_{ts}.json")
        w = np.asarray(self._last_wave).reshape(-1)
        x = np.arange(w.size)
        try:
            fs = getattr(self, "_last_fs", None)
            t = (x / fs) if fs else x.astype(np.float64)
            np.savetxt(csv_path, np.column_stack([t, w]),
                       delimiter=",", header="time_s,voltage_v", comments="")
            with open(json_path, "w", encoding="utf-8") as f:
                json.dump({"time_s": t.tolist(), "voltage_v": w.tolist()}, f)
            self.log.log("ok", f"已导出波形: {csv_path}")
        except Exception as e:
            self.log.log("error", f"导出失败: {e}")

    def on_save_snapshot(self):
        """保存单次采集的波形数据到 Excel"""
        if not hasattr(self, "_last_wave") or self._last_wave is None:
            QMessageBox.warning(self, "提示", "暂无波形可保存，请先进行单次采集")
            return
        
        try:
            from utils.excel_io import write_wave_excel
            
            # 准备保存路径
            folder = self.save_path.text().strip()
            if not folder:
                QMessageBox.warning(self, "提示", "请先设置保存路径")
                return
            
            os.makedirs(folder, exist_ok=True)
            
            # 生成文件名（与轨迹扫描格式一致）
            ts = datetime.now().strftime('%Y%m%d_%H%M%S_%f')[:-3]
            
            # 获取当前位置信息（如果三轴已连接）
            if self.stage.is_connected:
                x_mm = float(self.stage.current_mm.get('X', 0.0))
                y_mm = float(self.stage.current_mm.get('Y', 0.0))
                z_mm = float(self.stage.current_mm.get('Z', 0.0))
                filename = f'波形数据_{ts}_X={x_mm:.2f}_Y={y_mm:.2f}_Z={z_mm:.2f}.xlsx'
            else:
                filename = f'波形数据_{ts}.xlsx'
            
            filepath = os.path.join(folder, filename)
            
            # 准备元数据
            wave_v = self._last_wave
            time_s = self._last_time_s
            fs = self._last_fs
            n = len(wave_v)
            meta = getattr(self, "_last_meta", {})
            ch = getattr(self, "_last_channel", 1)
            avg_text = getattr(self, "_last_avg_text", "无")
            
            # 计算周期和频率
            T = float(n) / float(fs) if fs > 0 else 0.0
            F = 1.0 / T if T > 0 else 0.0
            
            # 计算波形统计信息
            vpp = float(np.max(wave_v) - np.min(wave_v))
            vmax = float(np.max(wave_v))
            vmin = float(np.min(wave_v))
            vmean = float(np.mean(wave_v))
            vrms = float(np.sqrt(np.mean(wave_v**2)))
            
            # 构建元数据列表（与轨迹扫描格式一致）
            metadata_pairs = [
                ('采集时间', ts),
                ('通道', f'CH{ch}'),
                ('平均模式', avg_text),
                ('', ''),
                ('采样率(MSa/s)', fs / 1_000_000.0),
                ('请求点数(k点)', int(self.points_slider.value()) / 1000.0),
                ('返回点数(k点)', n / 1000.0),
                ('周期(s)', T),
                ('频率(Hz)', F),
                ('', ''),
                ('峰峰值(V)', vpp),
                ('最大值(V)', vmax),
                ('最小值(V)', vmin),
                ('平均值(V)', vmean),
                ('有效值(V)', vrms),
                ('', ''),
            ]
            
            # 添加位置信息（如果三轴已连接）
            if self.stage.is_connected:
                metadata_pairs.extend([
                    ('X位置(mm)', x_mm),
                    ('Y位置(mm)', y_mm),
                    ('Z位置(mm)', z_mm),
                    ('', ''),
                ])
            
            # 添加示波器元数据
            if meta:
                metadata_pairs.extend([
                    ('xincrement', meta.get('xincrement', 0)),
                    ('xorigin', meta.get('xorigin', 0)),
                    ('xreference', meta.get('xreference', 0)),
                    ('yincrement', meta.get('yincrement', 0)),
                    ('yorigin', meta.get('yorigin', 0)),
                    ('yreference', meta.get('yreference', 0)),
                ])
            
            # 写入 Excel 文件
            write_wave_excel(filepath, metadata_pairs, time_s, wave_v)
            
            self.log.log("ok", f"波形已保存: {filename}")
            QMessageBox.information(self, "保存成功", 
                f"波形数据已保存至:\n{filepath}\n\n"
                f"采样率: {fs/1e6:.3f} MSa/s\n"
                f"采集点数: {n} 点\n"
                f"峰峰值: {vpp:.6f} V")
            
        except ModuleNotFoundError as e:
            QMessageBox.critical(self, "错误", str(e))
            self.log.log("error", str(e))
        except Exception as e:
            QMessageBox.critical(self, "保存失败", str(e))
            self.log.log("error", f"保存波形失败: {e}")

    # ════════════════════════════════════════════════════════════════
    #  Motion
    # ════════════════════════════════════════════════════════════════

    def _require_stage(self):
        if not self.stage.is_connected:
            QMessageBox.warning(self, "提示", "请先连接三轴")
            return False
        return True

    def on_continuous_move(self):
        if not self._require_stage():
            return
        try:
            tx = _safe_float(self.c_x.text(), 0.0)
            ty = _safe_float(self.c_y.text(), 0.0)
            tz = _safe_float(self.c_z.text(), 0.0)
            self._lock_controls(True)
            self.stage.move_axis_abs("X", tx)
            self.stage.move_axis_abs("Y", ty)
            self.stage.move_axis_abs("Z", tz)
            self.log.log("ok", f"连续位移完成: X={tx:.2f}, Y={ty:.2f}, Z={tz:.2f}")
        except Exception as e:
            QMessageBox.critical(self, "连续位移失败", str(e))
            self.log.log("error", str(e))
        finally:
            self._lock_controls(False)
            self.refresh_status()

    def on_interval_scan(self):
        if not self._require_stage():
            return
        if not self.scope.is_connected:
            QMessageBox.warning(self, "提示", "间隔扫描需要示波器，请先连接示波器")
            return
        try:
            target_x = _safe_float(self.i_x.text(), 0.0)
            target_y = _safe_float(self.i_y.text(), 0.0)
            target_z = _safe_float(self.i_z.text(), 0.0)
            step = max(0.01, _safe_float(self.interval_mm.text(), 0.1))
            pre = max(0.0, _safe_float(self.pre_delay.text(), 0.5))
            xdiff = target_x - float(self.stage.current_mm.get("X", 0.0))
            ydiff = target_y - float(self.stage.current_mm.get("Y", 0.0))
            zdiff = target_z - float(self.stage.current_mm.get("Z", 0.0))
            ch = int(self.scope_channel.currentText())
            pts = int(self.points_slider.value())
            
            # 根据成像模式重置数据
            if self.imaging_mode == "transmission":
                self.transmission_data = []
                self.transmission_grid = {}
                # 记录步距信息（用于透射成像的像素块大小）
                self.transmission_step_x = step
                self.transmission_step_y = step
            else:
                self.bmode_cache.reset()
            
            self.img_item.setImage(np.zeros((2, 2), dtype=np.float32), autoLevels=False, levels=(0.0, 1.0))

            # 设置平均模式（如果选择了）
            avg_text = self.avg_combo.currentText()
            if avg_text != "无" and self.scope.is_connected:
                count = int(avg_text.replace("次", ""))
                self.scope.set_average_mode(count)
                self.log.log("info", f"间隔扫描使用平均 {count} 次采集")

            self.scan_worker = IntervalScanWorker(
                self.scope, self.stage, self.save_path.text().strip(),
                ch, pts, xdiff, ydiff, zdiff, step, pre
            )
            self.scan_worker.log.connect(lambda m: self.log.log("info", m))
            self.scan_worker.step_acquired.connect(self._on_interval_step)
            self.scan_worker.failed.connect(
                lambda m: (self.log.log("error", m), QMessageBox.critical(self, "间隔扫描失败", m))
            )
            self.scan_worker.finished.connect(lambda: self.log.log("ok", "间隔扫描完成"))
            self._lock_controls(True)
            self.scan_worker.start()
            self.log.log("info", "间隔扫描启动")
        except Exception as e:
            QMessageBox.critical(self, "间隔扫描错误", str(e))
            self.log.log("error", str(e))
            self._lock_controls(False)

    def _on_interval_step(self, payload: dict):
        """处理间隔扫描的每一步（参考 MATLAB updateBModeAfterAcquisition）"""
        self.log.log("info", "========== _on_interval_step 被调用 ==========")
        try:
            wave_v = np.asarray(payload["wave_v"], dtype=np.float32)
            fs = float(payload["fs"])
            n = int(payload["n"])
            x_mm = float(payload.get("x_mm", 0.0))
            y_mm = float(payload.get("y_mm", 0.0))
            z_mm = float(payload.get("z_mm", 0.0))
            excel_path = payload.get("excel_path", "")
            
            self.log.log("info", f"收到数据: wave_v.shape={wave_v.shape}, fs={fs}, n={n}, x={x_mm}, y={y_mm}, z={z_mm}")
            
            # 更新波形显示
            self._last_wave = wave_v
            self._last_fs = fs
            
            # 打印调试信息
            meta = payload.get("meta", {})
            self.log.log("info", f"波形数据: 范围={wave_v.min():.6f}~{wave_v.max():.6f}V, 点数={len(wave_v)}")
            self.log.log("info", f"前导信息: yincrement={meta.get('yincrement', 'N/A')}, yorigin={meta.get('yorigin', 'N/A')}, yreference={meta.get('yreference', 'N/A')}")
            
            time_s = payload.get("time_s")
            if time_s is not None:
                # 使用示波器返回的真实时间轴（与示波器显示一致）
                t_us = np.asarray(time_s, dtype=np.float32) * 1e6
            else:
                # 备用：如果没有 time_s，用采样率计算相对时间
                x = np.arange(wave_v.size, dtype=np.int32)
                t_us = (x / fs) * 1e6 if fs > 0 else x
            self.wave_curve.setData(t_us, self._apply_spike_filter(wave_v))

            # 根据成像模式处理数据
            if self.imaging_mode == "transmission":
                # 透射成像模式：提取指定时间范围内的峰峰值
                vpp = self._extract_transmission_vpp(wave_v, fs, n, time_s=payload.get("time_s"))
                
                # 计算网格坐标（基于当前位置）
                # 假设从(0,0)开始，按Y方向扫描
                x_idx = int(round(x_mm / self.transmission_step_x)) if self.transmission_step_x > 0 else 0
                y_idx = int(round(y_mm / self.transmission_step_y)) if self.transmission_step_y > 0 else 0
                
                self.transmission_data.append({
                    "vpp": vpp,
                    "x_mm": x_mm,
                    "y_mm": y_mm,
                    "z_mm": z_mm,
                    "x_idx": x_idx,
                    "y_idx": y_idx
                })
                self.transmission_grid[(x_idx, y_idx)] = vpp
                
                time_start, time_end = self.transmission_time_range
                self.log.log("info", f"透射成像: ({x_idx},{y_idx}) @ ({x_mm:.2f},{y_mm:.2f})mm, 时间范围{time_start:.2f}~{time_end:.2f}µs, Vpp={vpp:.6f}V")
                self._update_transmission_image()
            else:
                # B 模式成像
                # 更新 B 模式参数
                self.bmode_cache.dr_db = float(self.slider_dr.value())
                self.bmode_cache.contrast_gain = float(self.slider_contrast.value()) / 100.0
                
                # 添加 B 模式列（使用 Y 位置作为横向坐标，参考 MATLAB）
                self.log.log("info", f"处理波形: fs={fs/1e6:.2f}MSa/s, n={n}, Y={y_mm:.2f}mm, 波形范围={wave_v.min():.6f}~{wave_v.max():.6f}V")
                
                bmode_db = self.bmode_cache.add_line(wave_v, fs_hz=fs, sample_length=n, lateral_mm=y_mm)
                
                if bmode_db is not None:
                    # 记录 B 模式信息
                    cols = bmode_db.shape[1]
                    rows = bmode_db.shape[0]
                    db_min = float(bmode_db.min())
                    db_max = float(bmode_db.max())
                    
                    self.log.log("info", f"B模式矩阵: {rows}x{cols}, dB范围: {db_min:.2f}~{db_max:.2f}, 全局最大包络: {self.bmode_cache.global_env_max:.6e}")
                    
                    # 更新图像显示（模仿 MATLAB imagesc + CLim）
                    dr = self.bmode_cache.dr_db
                    depth_mm_arr = self.bmode_cache.depth_mm
                    lat_arr = np.array(self.bmode_cache.lateral_mm, dtype=np.float32)
                    img_data = bmode_db.T.copy()  # (lateral, depth)
                    # 先 setImage，再应用 LUT（顺序很重要）
                    self.img_item.setImage(img_data, autoLevels=False, levels=(-dr, 0.0))
                    self._apply_cmap(self.cmap.currentText())  # 每次刷新后重新应用 LUT
                    # 设置坐标系
                    if depth_mm_arr is not None and lat_arr.size >= 1:
                        x0 = float(lat_arr[0])
                        x1 = float(lat_arr[-1]) if lat_arr.size > 1 else x0 + 1.0
                        y0 = float(depth_mm_arr[0])
                        y1 = float(depth_mm_arr[-1])
                        pw = abs(x1 - x0) if lat_arr.size > 1 else 1.0
                        ph = abs(y1 - y0) if abs(y1 - y0) > 1e-6 else 1.0
                        self.img_item.setRect(QRectF(min(x0, x1), y0, pw, ph))
                    self.log.log("ok", f"B模式已更新: {cols}列, Y={y_mm:.2f}mm, DR={dr:.0f}dB")
                else:
                    self.log.log("error", "B模式更新失败: add_line 返回 None")
            
            # 记录数据保存
            if excel_path:
                self.log.log("ok", f"数据已保存: {excel_path}")
            
            self.refresh_status()
            
        except Exception as e:
            self.log.log("error", f"处理间隔步骤失败: {str(e)}")
            import traceback
            self.log.log("error", traceback.format_exc())

    def on_trajectory_scan(self):
        if not self._require_stage():
            return
        if not self.scope.is_connected:
            QMessageBox.warning(self, "提示", "轨迹扫描需要示波器，请先连接示波器")
            return
        
        # 检查系统是否初始化
        if not self.stage.is_initialized:
            QMessageBox.warning(self, "提示", "轨迹扫描需要先初始化系统！\n请点击'⚙ 初始化系统'按钮")
            return
        
        try:
            # 获取轴选择
            axis_span = self.t_axis_span.currentText()  # 行程轴
            axis_lines = self.t_axis_lines.currentText()  # 行数轴（同时也是步距轴）

            # 获取参数
            span_val = max(0.01, _safe_float(self.t_xspan.text(), 10.0))
            step_val = max(0.01, _safe_float(self.t_xstep.text(), 1.0))
            line_step_val = max(0.01, _safe_float(self.t_ystep.text(), 1.0))
            line_count = max(1, _safe_int(self.t_ylines.text(), 10))

            startAtCurrent = (self.t_start.currentIndex() == 0)
            saveEach = (self.t_save.currentIndex() == 0)
            ch = int(self.scope_channel.currentText())
            pts = int(float(self.acq_points_edit.text().strip()) * 1000)

            # 行程轴和行数轴必须不同
            if axis_span == axis_lines:
                QMessageBox.warning(self, "提示", "行程轴和行数轴不能相同！")
                return

            # 映射到 X/Y 坐标
            # 假设：行程轴做主扫描（对应 X），行数轴做副扫描（对应 Y）
            xSpan = span_val
            xStep = step_val
            yStep = line_step_val
            yLines = line_count

            # 获取采集前等待时间（从间隔位移面板的"等待"控件）
            preDelay = max(0.0, _safe_float(self.pre_delay.text(), 0.5))

            # 设置平均模式（如果选择了）
            avg_text = self.avg_combo.currentText()
            if avg_text != "无" and self.scope.is_connected:
                count = int(avg_text.replace("次", ""))
                self.scope.set_average_mode(count)
                self.log.log("info", f"轨迹扫描使用平均 {count} 次采集")

            self.log.log("info", f"轨迹扫描配置: 行程轴={axis_span}({span_val}mm), 行数轴={axis_lines}(行步距{line_step_val}mm), 行数={line_count}, 采集前等待={preDelay}s")

            # 传递轴选择给 worker
            self.traj_worker = TrajectoryScanWorker(
                self.scope, self.stage, self.save_path.text().strip(),
                ch, pts, xSpan, xStep, yStep, yLines,
                start_at_current=startAtCurrent,
                acquire_each_point=saveEach,
                dr_db=float(self.slider_dr.value()),
                contrast_gain=float(self.slider_contrast.value()) / 100.0,
                c_sound_m_s=1540.0,
                span_axis=axis_span,
                step_axis=axis_lines,
                pre_delay_s=preDelay
            )
            self.traj_worker.log.connect(lambda m: self.log.log("info", m))
            self.traj_worker.plane_update.connect(self._on_traj_plane)
            self.traj_worker.point_acquired.connect(self._on_traj_point_acquired)
            self.traj_worker.failed.connect(
                lambda m: (self.log.log("error", m),
                           QMessageBox.critical(self, "轨迹失败", m),
                           self._lock_controls(False))
            )
            self.traj_worker.finished.connect(self._on_traj_finished)
            self._lock_controls(True)
            self.traj_worker.start()
            self.log.log("info", "轨迹扫描启动")
        except Exception as e:
            QMessageBox.critical(self, "轨迹错误", str(e))
            self.log.log("error", str(e))
            self._lock_controls(False)

    def _on_traj_plane(self, info: dict):
        # B模式成像更新 - 只在B模式下更新
        if self.imaging_mode != "transmission":
            img_db = np.asarray(info["img_db"], dtype=np.float32)
            dr = float(self.slider_dr.value())
            self.img_item.setImage(img_db.T.copy(), autoLevels=False, levels=(-dr, 0.0))
        self.refresh_status()

    def _on_traj_point_acquired(self, payload: dict):
        """处理轨迹位移的单点采集数据 - 用于透射成像和波形显示"""
        try:
            wave_v = payload.get("wave_v")
            fs = payload.get("fs", 0)
            n = payload.get("n", 0)
            time_s = payload.get("time_s")
            x_mm = payload.get("x_mm", 0.0)
            y_mm = payload.get("y_mm", 0.0)
            z_mm = payload.get("z_mm", 0.0)

            # 更新波形图显示（轨迹位移也需要显示波形）
            if wave_v is not None and wave_v.size > 0:
                if time_s is not None:
                    t_us = np.asarray(time_s, dtype=np.float32) * 1e6
                else:
                    x = np.arange(wave_v.size, dtype=np.int32)
                    t_us = (x / fs) * 1e6 if fs > 0 else x
                self.wave_curve.setData(t_us, self._apply_spike_filter(wave_v))

            # 透射成像处理
            if self.imaging_mode == "transmission":
                vpp = self._extract_transmission_vpp(wave_v, fs, n, time_s=time_s)

                # 获取轨迹扫描的轴配置
                span_axis = getattr(self.traj_worker, 'span_axis', 'X')
                step_axis = getattr(self.traj_worker, 'step_axis', 'Y')

                # 获取行号和行内点号（从1开始）
                line_idx = payload.get('line_idx', 1)      # 行号（对应步距轴）
                point_idx = payload.get('point_idx', 1)    # 行内点号（对应行程轴）
                dir_sign = payload.get('dir_sign', 1.0)    # 扫描方向
                points_per_line = payload.get('points_per_line', 1)  # 每行点数

                # 计算网格索引（从0开始）
                # span_idx: 行程轴方向（列）
                # step_idx: 步距轴方向（行）
                step_idx = line_idx - 1  # 行号直接对应步距轴索引

                # 根据扫描方向计算行程轴索引
                # 正向（dir_sign=1）：point_idx 从 1 到 N，对应 span_idx 从 0 到 N-1
                # 反向（dir_sign=-1）：point_idx 从 1 到 N，对应 span_idx 从 N-1 到 0
                if dir_sign > 0:
                    span_idx = point_idx - 1
                else:
                    span_idx = points_per_line - point_idx

                # 存储透射数据
                self.transmission_data.append({
                    "vpp": vpp,
                    "span_idx": span_idx,
                    "step_idx": step_idx,
                    "line_idx": line_idx,
                    "point_idx": point_idx,
                    "x_mm": x_mm,
                    "y_mm": y_mm,
                    "z_mm": z_mm
                })
                self.transmission_grid[(span_idx, step_idx)] = vpp

                # 更新透射成像显示
                self._update_transmission_image_traj(span_axis, step_axis)

                self.log.log("info", f"透射成像: 网格({span_idx},{step_idx}) 行{line_idx}点{point_idx} Vpp={vpp:.6f}V")
        except Exception as e:
            self.log.log("error", f"轨迹点处理失败: {str(e)}")

    def _on_traj_finished(self, res: dict):
        self.log.log("ok", f"轨迹完成: {res.get('mat_path', '')}")
        self._lock_controls(False)
        self.refresh_status()

    def on_stop_all(self):
        for w in [self.scan_worker, self.traj_worker]:
            try:
                if w and w.is_running:
                    w.stop()
            except Exception:
                pass
        try:
            if self.stage.is_connected:
                self.stage.stop()
        except Exception:
            pass
        self._lock_controls(False)
        self.log.log("warn", "已请求停止")
        self.refresh_status()

    def _lock_controls(self, busy: bool):
        for w in [self.btn_cont_exec, self.btn_int_exec, self.btn_traj_exec]:
            w.setEnabled(not busy)
        for w in [self.btn_cont_stop, self.btn_int_stop, self.btn_traj_stop]:
            w.setEnabled(True)

    # ════════════════════════════════════════════════════════════════
    #  B-Mode
    # ════════════════════════════════════════════════════════════════

    def _on_imaging_mode_changed(self, mode_text: str):
        """切换成像模式"""
        is_transmission = (mode_text == "透射成像")
        self.imaging_mode = "transmission" if is_transmission else "bmode"
        
        # 更新成像区域的标题
        if is_transmission:
            self.bmode_card.setTitle("透射成像")
        else:
            self.bmode_card.setTitle("B 模式成像")
        
        # 显示/隐藏对应的控制器
        self.slider_contrast.setVisible(not is_transmission)
        self.slider_dr.setVisible(not is_transmission)
        self.slider_time_start.setVisible(is_transmission)
        self.slider_time_end.setVisible(is_transmission)
        self.vpp_norm_lbl.setVisible(is_transmission)
        self.vpp_norm_edit.setVisible(is_transmission)
        self.vpp_norm_unit.setVisible(is_transmission)
        self.btn_show_vpp_labels.setVisible(is_transmission)
        
        # 清空图像
        self.img_item.setImage(np.zeros((2, 2), dtype=np.float32), autoLevels=False, levels=(0.0, 1.0))
        
        if is_transmission:
            self.log.log("info", "已切换到透射成像模式 - 显示时间范围滑块")
            self._update_transmission_time_range()
        else:
            self.log.log("info", "已切换到 B 模式 - 显示对比度和DR滑块")

    def _on_bmode_adjust(self, _=None):
        try:
            if self.bmode_cache.bmode_db is not None:
                self.bmode_cache.dr_db = float(self.slider_dr.value())
                self.bmode_cache.contrast_gain = float(self.slider_contrast.value()) / 100.0
        except Exception:
            pass

    def _on_transmission_adjust(self, _=None):
        """透射成像参数调整"""
        self._update_transmission_time_range()
        # 如果已有数据，立即更新显示
        if self.transmission_data:
            self._update_transmission_image()

    def _update_transmission_time_range(self):
        """更新时间范围"""
        time_start = float(self.slider_time_start.value())
        time_end = float(self.slider_time_end.value())
        if time_start > time_end:
            time_start, time_end = time_end, time_start
        self.transmission_time_range = (time_start, time_end)
        self.log.log("info", f"时间范围: {time_start:.2f}µs ~ {time_end:.2f}µs")

    def _update_time_slider_range(self, time_min_us: float, time_max_us: float):
        """根据波形时间轴更新时间范围滑块的范围"""
        try:
            # 将时间范围转换为整数（滑块值）
            min_val = int(np.floor(time_min_us))
            max_val = int(np.ceil(time_max_us))
            
            # 更新滑块范围
            self.slider_time_start.slider.setRange(min_val, max_val)
            self.slider_time_end.slider.setRange(min_val, max_val)
            
            # 设置默认值：起点为最小值，终点为最大值
            self.slider_time_start.slider.setValue(min_val)
            self.slider_time_end.slider.setValue(max_val)
            
            self.log.log("info", f"时间滑块范围已更新: {min_val}~{max_val}µs")
        except Exception as e:
            self.log.log("error", f"更新时间滑块范围失败: {str(e)}")

    def _extract_transmission_vpp(self, wave_v: np.ndarray, fs_hz: float, sample_length: int, time_s: np.ndarray = None) -> float:
        """从指定时间范围内的波形提取峰峰值（带信号预处理滤波）"""
        w = np.asarray(wave_v, dtype=np.float64).reshape(-1)
        if sample_length <= 0:
            return 0.0
        w = w[:sample_length]

        # 确定时间轴
        if time_s is not None:
            t_us = np.asarray(time_s, dtype=np.float64) * 1e6
        else:
            x = np.arange(w.size, dtype=np.int32)
            t_us = (x / fs_hz) * 1e6 if fs_hz > 0 else x.astype(np.float64)

        # 提取指定时间范围内的数据
        time_start, time_end = self.transmission_time_range
        mask = (t_us >= time_start) & (t_us <= time_end)

        if not np.any(mask):
            # 如果没有数据在范围内，返回 0
            return 0.0

        w_range = w[mask]

        # 信号预处理滤波 - 针对250kHz探头优化
        if hasattr(self, 'signal_filter') and self.signal_filter.filter_enabled:
            # 更新滤波器采样率
            self.signal_filter.fs_hz = fs_hz

            # 应用250kHz探头专用滤波流程
            w_filtered = self.signal_filter.full_process_250khz(
                w_range,
                use_notch=True,      # 多谐波陷波（50,100,150,200,250Hz）
                use_savgol=True,     # Savitzky-Golay平滑（不依赖PyWavelets）
                use_bg_sub=True      # 背景扣除
            )
            w_range = w_filtered

        # 计算滤波后信号的峰峰值
        vpp = float(np.max(w_range) - np.min(w_range)) if w_range.size else 0.0
        return vpp

    def _capture_background_signal(self, wave_v: np.ndarray, fs_hz: float):
        """采集背景参考信号用于扣除"""
        self.background_signal = np.asarray(wave_v, dtype=np.float64)
        if hasattr(self, 'signal_filter'):
            self.signal_filter.set_background(self.background_signal)
        self.log.log("info", f"背景信号已采集: {len(self.background_signal)} 点, 采样率 {fs_hz/1e6:.2f} MSa/s")

    def _update_transmission_image(self):
        """更新透射成像图像 - 间隔位移模式"""
        self._update_transmission_image_internal("X", "Y", self.transmission_step_x, self.transmission_step_y)

    def _update_transmission_image_traj(self, span_axis: str, step_axis: str):
        """更新透射成像图像 - 轨迹位移模式

        Args:
            span_axis: 行程轴名称 (X/Y/Z)
            step_axis: 步距轴名称 (X/Y/Z)
        """
        if self.traj_worker:
            span_step = self.traj_worker.x_step_mm
            step_step = self.traj_worker.y_step_mm
        else:
            span_step = 1.0
            step_step = 1.0
        self._update_transmission_image_internal(span_axis, step_axis, span_step, step_step)

    def _update_transmission_image_internal(self, span_axis: str, step_axis: str, span_step: float, step_step: float):
        """更新透射成像图像 - 内部实现

        Args:
            span_axis: 行程轴名称（显示为X轴）
            step_axis: 步距轴名称（显示为Y轴）
            span_step: 行程轴步距
            step_step: 步距轴步距
        """
        # 持久化轴/步距信息，供动态重渲染时使用
        self._transmission_span_axis = span_axis
        self._transmission_step_axis = step_axis
        self._transmission_span_step = span_step
        self._transmission_step_step = step_step

        if not self.transmission_grid:
            return

        try:
            # 获取网格的范围
            indices = list(self.transmission_grid.keys())
            span_indices = [idx[0] for idx in indices]
            step_indices = [idx[1] for idx in indices]

            span_min, span_max = min(span_indices), max(span_indices)
            step_min, step_max = min(step_indices), max(step_indices)

            # 创建图像矩阵 - 注意：pyqtgraph的图像是[row, col] = [y, x]
            # 我们要显示：X轴=行程轴（横向），Y轴=步距轴（纵向）
            img_height = step_max - step_min + 1  # Y方向（步距轴）
            img_width = span_max - span_min + 1   # X方向（行程轴）
            img_array = np.zeros((img_height, img_width), dtype=np.float32)

            # 收集所有峰峰值用于归一化
            vpp_values = np.array(list(self.transmission_grid.values()), dtype=np.float32)
            vpp_min = 0.0  # 归一化下限固定为 0
            # 归一化上限：优先使用用户输入值，否则自动取最大值
            try:
                txt = self.vpp_norm_edit.text().strip()
                vpp_norm_max = float(txt) if txt else 0.0
            except (ValueError, AttributeError):
                vpp_norm_max = 0.0
            if vpp_norm_max <= 0:
                vpp_norm_max = float(np.max(vpp_values)) if vpp_values.size > 0 else 1.0
            vpp_range = vpp_norm_max if vpp_norm_max > 0 else 1.0

            # 填充图像矩阵
            for (span_idx, step_idx), vpp in self.transmission_grid.items():
                col = span_idx - span_min  # X轴（行程轴）
                row = step_max - step_idx  # Y轴（步距轴），翻转使Y向上增长
                normalized = np.clip(vpp / vpp_range, 0.0, 1.0)
                if 0 <= row < img_height and 0 <= col < img_width:
                    img_array[row, col] = normalized

            # 显示图像（转置：pyqtgraph 第一轴为 X，第二轴为 Y）
            self.img_item.setImage(img_array.T, autoLevels=False, levels=(0.0, 1.0))

            # 应用当前用户选择的 colormap
            self._apply_cmap(self.cmap.currentText())

            # 计算物理坐标范围
            # X轴（行程轴）：从左到右
            x0 = span_min * span_step
            x1 = (span_max + 1) * span_step
            # Y轴（步距轴）：从下到上
            y0 = step_min * step_step
            y1 = (step_max + 1) * step_step

            width = x1 - x0
            height = y1 - y0

            # 设置图像的物理位置和大小
            self.img_item.setRect(QRectF(x0, y0, width, height))

            # 设置坐标轴范围和标签
            self.bmode_plot.setXRange(x0, x1, padding=0.05)
            self.bmode_plot.setYRange(y0, y1, padding=0.05)

            # 设置坐标轴标签
            self.bmode_plot.setLabel('bottom', f'行程轴 ({span_axis}) (mm)')
            self.bmode_plot.setLabel('left', f'步距轴 ({step_axis}) (mm)')

            # 设置等比例显示 - 确保X和Y轴的物理单位相同
            self.bmode_plot.setAspectLocked(True, ratio=1.0)

            # 重建 Vpp 数值标注
            self._rebuild_vpp_labels(span_step, step_step)

            self.log.log("ok", f"透射成像已更新: {img_width}×{img_height}像素, "
                        f"行程轴({span_axis}): {span_min}~{span_max} (步距{span_step}mm), "
                        f"步距轴({step_axis}): {step_min}~{step_max} (步距{step_step}mm), "
                        f"Vpp范围: {vpp_min:.6f}~{vpp_max:.6f}V")
        except Exception as e:
            self.log.log("error", f"透射成像更新失败: {str(e)}")

    def _on_vpp_norm_changed(self):
        """最大值输入框回车/失焦后，用现有数据重新渲染热力图。"""
        if self.transmission_grid:
            self._update_transmission_image_internal(
                self._transmission_span_axis,
                self._transmission_step_axis,
                self._transmission_span_step,
                self._transmission_step_step,
            )

    def _rebuild_vpp_labels(self, span_step: float, step_step: float):
        """清除旧标注，根据 transmission_grid 重建每格 Vpp 文字。"""
        # 清除旧标注
        for item in self._vpp_text_items:
            self.bmode_plot.removeItem(item)
        self._vpp_text_items.clear()

        if not self.transmission_grid:
            return

        show = hasattr(self, 'btn_show_vpp_labels') and self.btn_show_vpp_labels.isChecked()

        for (span_idx, step_idx), vpp in self.transmission_grid.items():
            # 色块中心物理坐标
            x_c = span_idx * span_step + span_step * 0.5
            y_c = step_idx * step_step + step_step * 0.5
            # 格式化：mV 或 V
            if abs(vpp) < 1.0:
                txt = f"{vpp * 1000:.1f}mV"
            else:
                txt = f"{vpp:.3f}V"
            item = pg.TextItem(txt, color=(255, 255, 255, 220), anchor=(0.5, 0.5))
            item.setFont(QFont("Consolas", 7))
            item.setPos(x_c, y_c)
            item.setVisible(show)
            self.bmode_plot.addItem(item)
            self._vpp_text_items.append(item)

    def _on_toggle_vpp_labels(self, checked: bool):
        """切换热力图上 Vpp 数值的显示/隐藏。"""
        for item in self._vpp_text_items:
            item.setVisible(checked)

    def _apply_cmap(self, name: str):
        import numpy as _np
        from pyqtgraph import ColorMap as _ColorMap

        def _gray():
            pos = _np.linspace(0.0, 1.0, 256)
            cols = _np.stack([pos, pos, pos, _np.ones_like(pos)], axis=1)
            return _ColorMap(pos, cols)

        def _rainbow():
            """256色精细彩虹：蓝→青→绿→黄→橙→红，每级唯一颜色"""
            x = _np.linspace(0.0, 1.0, 256)
            # 关键节点（位置, R, G, B）
            nodes = [
                (0.00, 0.00, 0.00, 0.50),  # 深蓝
                (0.15, 0.00, 0.00, 1.00),  # 蓝
                (0.30, 0.00, 0.50, 1.00),  # 青蓝
                (0.40, 0.00, 1.00, 1.00),  # 青
                (0.50, 0.00, 1.00, 0.00),  # 绿
                (0.60, 0.50, 1.00, 0.00),  # 黄绿
                (0.75, 1.00, 1.00, 0.00),  # 黄
                (0.85, 1.00, 0.50, 0.00),  # 橙
                (0.95, 1.00, 0.00, 0.00),  # 红
                (1.00, 0.50, 0.00, 0.00),  # 深红
            ]
            # 分段线性插值
            r = _np.interp(x, [n[0] for n in nodes], [n[1] for n in nodes])
            g = _np.interp(x, [n[0] for n in nodes], [n[2] for n in nodes])
            b = _np.interp(x, [n[0] for n in nodes], [n[3] for n in nodes])
            cols = _np.stack([r, g, b, _np.ones_like(r)], axis=1)
            return _ColorMap(_np.linspace(0.0, 1.0, 256), cols)

        def _blue_yellow():
            """蓝-黄双色渐变：低值蓝色，高值黄色，中间自然过渡"""
            x = _np.linspace(0.0, 1.0, 256)
            # 蓝色 (0, 0, 1) -> 黄色 (1, 1, 0)
            # 红色：0 -> 1
            r = x
            # 绿色：0 -> 1
            g = x
            # 蓝色：1 -> 0
            b = 1.0 - x
            cols = _np.stack([r, g, b, _np.ones_like(r)], axis=1)
            return _ColorMap(_np.linspace(0.0, 1.0, 256), cols)

        def _hot():
            x = _np.linspace(0.0, 1.0, 256)
            r = _np.clip(3 * x, 0, 1)
            g = _np.clip(3 * x - 1, 0, 1)
            b = _np.clip(3 * x - 2, 0, 1)
            cols = _np.stack([r, g, b, _np.ones_like(r)], axis=1)
            return _ColorMap(_np.linspace(0.0, 1.0, 256), cols)

        try:
            cm = {"灰度": _gray, "彩虹": _rainbow, "蓝黄": _blue_yellow}.get(name, _hot)()
            # getLookupTable 返回 float[0,1]，需转为 uint8[0,255]
            lut_f = cm.getLookupTable(nPts=256, alpha=False)
            lut = (_np.clip(lut_f, 0.0, 1.0) * 255).astype(_np.uint8)
            self.img_item.setLookupTable(lut)
        except Exception as e:
            print(f"_apply_cmap error: {e}")

    # ════════════════════════════════════════════════════════════════
    #  Measurements
    # ════════════════════════════════════════════════════════════════

    def _set_meas_exclusive(self, which: str):
        for key, btn in [("peak", self.btn_meas_peak),
                         ("mean", self.btn_meas_mean),
                         ("freq", self.btn_meas_freq)]:
            if key != which:
                try:
                    btn.blockSignals(True)
                    btn.setChecked(False)
                finally:
                    btn.blockSignals(False)

    def on_meas_peak(self):
        if not self.btn_meas_peak.isChecked():
            self.lbl_meas.setText("—")
            try:
                self.meas_text.setText("")
            except Exception:
                pass
            return
        if not hasattr(self, "_last_wave"):
            return
        w = np.asarray(self._last_wave, dtype=np.float64)
        peak = float(np.max(w))
        trough = float(np.min(w))
        vpp = peak - trough
        txt = f"Peak={peak:.4g} V  Vpp={vpp:.4g} V"
        self.lbl_meas.setText(txt)
        try:
            self.meas_text.setText(f"Peak={peak:.4g}V\nVpp={vpp:.4g}V")
        except Exception:
            pass

    def on_meas_mean(self):
        if not self.btn_meas_mean.isChecked():
            self.lbl_meas.setText("—")
            try:
                self.meas_text.setText("")
            except Exception:
                pass
            return
        if not hasattr(self, "_last_wave"):
            return
        w = np.asarray(self._last_wave, dtype=np.float64)
        mean = float(np.mean(w))
        rms = float(np.sqrt(np.mean(np.square(w))))
        txt = f"Mean={mean:.4g} V  RMS={rms:.4g} V"
        self.lbl_meas.setText(txt)
        try:
            self.meas_text.setText(f"Mean={mean:.4g}V\nRMS={rms:.4g}V")
        except Exception:
            pass

    def on_meas_freq(self):
        if not self.btn_meas_freq.isChecked():
            self.lbl_meas.setText("—")
            try:
                self.meas_text.setText("")
            except Exception:
                pass
            return
        if not hasattr(self, "_last_wave") or not hasattr(self, "_last_fs"):
            return
        w = np.asarray(self._last_wave, dtype=np.float64)
        fs = float(self._last_fs)
        if fs <= 0 or w.size < 10:
            return
        f = np.fft.rfftfreq(w.size, d=1.0 / fs)
        spec = np.abs(np.fft.rfft(w - np.mean(w)))
        if spec.size < 3:
            return
        idx = int(np.argmax(spec[1:]) + 1)
        txt = f"Freq ≈ {f[idx]:.4g} Hz"
        self.lbl_meas.setText(txt)
        try:
            self.meas_text.setText(txt)
        except Exception:
            pass

    # ════════════════════════════════════════════════════════════════
    #  Mouse / Wave hover
    # ════════════════════════════════════════════════════════════════

    def _on_wave_mouse(self, pos):
        """优化版鼠标移动处理 - 更新十字光标和坐标显示"""
        if self.wave_plot.sceneBoundingRect().contains(pos):
            mp = self.wave_plot.plotItem.vb.mapSceneToView(pos)
            x, y = mp.x(), mp.y()
            
            # 更新十字光标位置
            if hasattr(self, 'crosshair_v'):
                self.crosshair_v.setPos(x)
                self.crosshair_h.setPos(y)
            
            # 更新坐标显示（优化格式）
            self.lbl_cursor.setText(f"x={x:.2f} µs, y={y:.3f} V")
            self.lbl_cursor.setStyleSheet(f"color:{ACCENT_LIGHT}; font-size:11px; font-family:Consolas; background:transparent;")

    # ════════════════════════════════════════════════════════════════
    #  Export log
    # ════════════════════════════════════════════════════════════════

    def on_export_log(self):
        try:
            save_dir = self.save_path.text().strip() or os.getcwd()
            os.makedirs(save_dir, exist_ok=True)
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            html_path = os.path.join(save_dir, f"log_{ts}.html")
            txt_path = os.path.join(save_dir, f"log_{ts}.txt")
            with open(html_path, "w", encoding="utf-8") as f:
                f.write(self.log.toHtml())
            with open(txt_path, "w", encoding="utf-8") as f:
                f.write(self.log.toPlainText())
            self.log.log("ok", f"日志已导出: {html_path}")
        except Exception as e:
            QMessageBox.critical(self, "导出日志失败", str(e))


# ─────────────────────────── Entry ───────────────────────────────
def main():
    app = QApplication(sys.argv)
    try:
        app.setFont(QFont("Microsoft YaHei", 12))
    except Exception:
        pass
    w = MainWindow()
    w.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
