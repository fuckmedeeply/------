# 透射成像信号预处理滤波模块

## 概述

为抑制电机驱动及电磁干扰引入的噪声，系统集成了多级信号预处理滤波模块。

## 滤波流程

### 1. 背景扣除（Background Subtraction）
- **作用**：消除系统性噪声基底
- **实现**：`background_subtraction()`
- **使用**：先采集无样品时的背景信号，后续采集自动扣除

### 2. 陷波滤波（Notch Filter）
- **作用**：滤除电机驱动频率及其谐波
- **默认参数**：
  - 基频：50 Hz
  - 陷波带宽：10 Hz
  - 谐波次数：5次
- **实现**：`notch_filter_motor()`

### 3. 带通滤波（Bandpass Filter）
- **作用**：限制有效频带，滤除高低频噪声
- **默认参数**：
  - 下限：100 kHz
  - 上限：5 MHz
- **实现**：4阶Butterworth带通滤波器

### 4. 小波去噪（Wavelet Denoising）
- **作用**：时域信号平滑，保留信号突变特征
- **默认参数**：
  - 小波基：db4 (Daubechies 4)
  - 分解层数：3层
  - 阈值系数：2.0（软阈值）
- **依赖**：PyWavelets库（可选）

### 5. 卡尔曼滤波（Kalman Filter）
- **作用**：自适应平滑时域信号
- **与小波去噪二选一使用**
- **适用**：缓慢变化的信号

## 使用方式

### 完整预处理流程
```python
from processing.signal_filter import SignalFilter

# 创建滤波器
flt = SignalFilter(fs_hz=10e6)  # 设置采样率

# 可选：设置背景信号
flt.set_background(bg_wave)

# 应用完整滤波
filtered_wave = flt.full_process(
    raw_wave,
    use_bandpass=True,   # 带通滤波
    use_notch=True,      # 陷波滤波
    use_wavelet=True,    # 小波去噪
    use_kalman=False,    # 卡尔曼滤波
    use_bg_sub=True      # 背景扣除
)
```

### 快速滤波
```python
from processing.signal_filter import quick_filter

filtered_wave = quick_filter(raw_wave, fs_hz=10e6, motor_freq=50.0)
```

## 效果验证

测试信号：500kHz 正弦波 + 50Hz 电机噪声

| 处理方式 | Vpp | 效果 |
|---------|-----|------|
| 原始信号 | 2.1540V | 含噪声 |
| 滤波后 | 2.1346V | 噪声抑制，信号保留 |

## 依赖安装

```bash
# 小波去噪需要
pip install PyWavelets>=1.4
```

## 注意事项

1. **采样率设置**：确保滤波器采样率与实际采样率一致
2. **背景采集**：在电机运行但无样品时采集背景信号
3. **参数调整**：可根据实际噪声特性调整滤波参数
