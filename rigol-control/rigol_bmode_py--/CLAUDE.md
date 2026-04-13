# CLAUDE.md

本文档为 Claude Code (claude.ai/code) 提供本代码库的工作指导。

## 项目概述

这是一个基于 PySide6 的 B 模式超声成像系统。它通过 PyVISA 控制 Rigol 示波器，并通过 RS485 控制三轴电机平台进行自动化声学扫描。该系统是 MATLAB 应用程序 (`Rigol_RS485x3_Bmode_2.m`) 的 Python 移植版本。

## 开发命令

```bash
# 环境搭建 (Windows)
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt

# 运行应用程序
python main.py

# 运行轨迹预览测试
python test_trajectory_preview.py
```

## 架构设计

### 硬件控制器 (`controllers/`)

- **`rigol_scope.py`** - `RigolScope` 类，通过 PyVISA/SCPI 命令与示波器通信。处理波形采集（RAW 和 NORM 模式）及设备配置。

- **`rs485_stage.py`** - `RS485Stage3Axis` 类，通过 RS485/Modbus 协议控制三轴电机。管理位置初始化、运动命令和坐标跟踪。

### 信号处理 (`processing/`)

- **`bmode_cache_matlab.py`** - `BModeCacheMatlab` 类，将扫描线累积成 B 模式图像，与 MATLAB 的处理流程保持一致。

- **`bmode_matlab.py`** - 核心 B 模式处理：包络检测（希尔伯特变换）、对数压缩、动态范围调整。设计与 MATLAB 输出结果匹配。

- **`signal_filter.py`** - `SignalFilter` 类，用于噪声抑制：背景扣除、陷波滤波（电机干扰）、带通滤波、小波去噪和卡尔曼滤波。

- **`trajectory_3d.py`** - 用于三维体积可视化的 MIP（最大强度投影）生成。

### 工作线程 (`workers.py`)

基于 Qt 的工作线程，用于非阻塞操作：
- **`AcquisitionWorker`** - 按指定间隔连续采集波形
- **`IntervalScanWorker`** - 基于网格的扫描，带位置步进
- **`TrajectoryScanWorker`** - 自定义轨迹跟踪（直线、圆形等）

### 工具类 (`utils/`)

- **`excel_io.py`** - 带元数据的波形数据 Excel 文件导出

## 关键实现说明

- **多线程**：所有硬件操作在独立的 QThread 中运行，以保持 UI 响应。主线程不应在硬件 I/O 上阻塞。

- **MATLAB 兼容性**：B 模式处理 (`bmode_matlab.py`) 旨在产生与原始 MATLAB 实现匹配的输出。算法细节请参考 `Rigol_RS485x3_Bmode_2.m`。

- **信号滤波**：滤波流程（背景扣除 → 陷波 → 带通 → 小波/卡尔曼）针对 250kHz 超声探头配置。默认带通：150-350 kHz。

- **RS485 协议**：电机命令使用带 CRC16 的 Modbus RTU。初始化需要 `INIT_HEX_COMMANDS` 中定义的特定十六进制命令序列。位置跟踪在软件中维护（开环）。

- **VISA 资源**：示波器通过 VISA 资源字符串连接（例如 `USB0::0x1AB1::0x0515::MS5A244909253::INSTR`）。应用程序在启动时扫描可用资源。

## 文件结构

```
main.py              # 主 GUI 应用程序 (PySide6)
workers.py           # 采集和扫描工作线程
controllers/         # 硬件接口类
processing/          # B 模式和信号处理算法
utils/               # I/O 工具类
requirements.txt     # 依赖：PySide6, pyvisa, pyserial, numpy, scipy 等
```
