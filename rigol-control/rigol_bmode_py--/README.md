# Rigol + RS485 x3 + B-mode (Python skeleton)

This is a **function-preserving port template** for your MATLAB app
`Rigol_RS485x3_Bmode_air_test_beautified.m`.

Implemented:
- PySide6 GUI layout (connect/disconnect, run/stop, single, acquire, movement mode stubs)
- Status banner + log
- B-mode display area (pyqtgraph ImageView)
- Threaded acquisition worker (non-blocking UI)
- Controller stubs for Rigol (PyVISA) and RS485 (pyserial)

To fill:
- Exact SCPI commands for your Rigol model & waveform readout/scaling
- Exact RS485 command set for your 3-axis stage
- B-mode processing parameters to match MATLAB pipeline (envelope/log-compress etc.)

Install:
    python -m venv .venv
    pip install -r requirements.txt

Run:
    python main.py
