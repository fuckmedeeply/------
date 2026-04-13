from __future__ import annotations
import numpy as np
from scipy.signal import hilbert

def matlab_bmode_column_db(
    wave_data: np.ndarray,
    fs_hz: float,
    sample_length: int,
    *,
    global_env_max: float,
    dr_db: float = 50.0,
    contrast_gain: float = 1.4,
    c_sound_m_s: float = 1540.0,
):
    if wave_data is None:
        return None, None, global_env_max
    w = np.asarray(wave_data, dtype=np.float64).reshape(-1)
    if sample_length <= 0:
        return None, None, global_env_max
    w = w[:sample_length]
    w = w - np.nanmean(w)
    env = np.abs(hilbert(w))
    env[~np.isfinite(env)] = 0.0
    local_max = float(np.max(env)) if env.size else 0.0
    if not np.isfinite(local_max) or local_max <= 0:
        local_max = np.finfo(np.float64).eps
    if global_env_max <= 0:
        global_env_max = local_max
    else:
        global_env_max = max(float(global_env_max), local_max)

    eps = np.finfo(np.float64).eps
    col_db = 20.0 * np.log10((env + eps) / global_env_max)
    col_db = col_db * float(contrast_gain)
    min_db = -float(dr_db)
    col_db[~np.isfinite(col_db)] = min_db
    col_db = np.clip(col_db, min_db, 0.0).astype(np.float32)

    depth_mm = (np.arange(sample_length, dtype=np.float64) * (float(c_sound_m_s) / (2.0 * float(fs_hz))) * 1000.0).astype(np.float32)
    return col_db, depth_mm, global_env_max
