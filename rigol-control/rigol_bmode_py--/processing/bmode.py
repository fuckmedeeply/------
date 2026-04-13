from __future__ import annotations
import numpy as np
from scipy.signal import hilbert

def bmode_from_rf(rf: np.ndarray, log_compress_db: float = 60.0) -> np.ndarray:
    rf = np.asarray(rf, dtype=np.float32)
    env = np.abs(hilbert(rf))
    env /= (env.max() + 1e-12)
    b = 20 * np.log10(env + 1e-12)
    b = np.clip(b, -log_compress_db, 0)
    b = (b + log_compress_db) / log_compress_db
    return b.reshape(-1, 1)
