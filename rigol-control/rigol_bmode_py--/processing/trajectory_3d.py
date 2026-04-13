from __future__ import annotations
import numpy as np

def envelope_column(wave_v: np.ndarray) -> np.ndarray:
    """Envelope should be computed outside if you already have it; placeholder."""
    raise NotImplementedError

def env_to_db(env: np.ndarray, ref: float, dr_db: float, contrast_gain: float) -> np.ndarray:
    eps = np.finfo(np.float64).eps
    ref = max(float(ref), eps)
    db = 20.0 * np.log10((env.astype(np.float64) + eps) / ref)
    db = db * float(contrast_gain)
    db[~np.isfinite(db)] = -float(dr_db)
    db = np.clip(db, -float(dr_db), 0.0)
    return db.astype(np.float32)

def mips(volume_db: np.ndarray):
    """
    MATLAB:
      mipXY = squeeze(max(volumeDb, [], 1));  -> (x, y)
      mipXZ = squeeze(max(volumeDb, [], 3));  -> (depth, x)
      mipYZ = squeeze(max(volumeDb, [], 2));  -> (depth, y)
    volume_db shape: (depth, x, y)
    """
    v = np.asarray(volume_db, dtype=np.float32)
    mip_xy = np.max(v, axis=0)  # (x,y)
    mip_xz = np.max(v, axis=2)  # (depth,x)
    mip_yz = np.max(v, axis=1)  # (depth,y)
    return mip_xy, mip_xz, mip_yz
