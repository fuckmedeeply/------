from __future__ import annotations
from dataclasses import dataclass, field
from typing import List, Optional
import numpy as np
from .bmode_matlab import matlab_bmode_column_db

@dataclass
class BModeCacheMatlab:
    dr_db: float = 50.0
    contrast_gain: float = 1.4
    c_sound_m_s: float = 1540.0

    global_env_max: float = 0.0
    bmode_db: Optional[np.ndarray] = None
    depth_mm: Optional[np.ndarray] = None
    lateral_mm: List[float] = field(default_factory=list)

    def reset(self):
        self.global_env_max = 0.0
        self.bmode_db = None
        self.depth_mm = None
        self.lateral_mm = []

    def add_line(self, wave_data, fs_hz: float, sample_length: int, lateral_mm: float):
        col_db, depth_mm, self.global_env_max = matlab_bmode_column_db(
            wave_data, fs_hz, sample_length,
            global_env_max=self.global_env_max,
            dr_db=self.dr_db, contrast_gain=self.contrast_gain, c_sound_m_s=self.c_sound_m_s
        )
        if col_db is None:
            return None

        if self.bmode_db is None:
            self.bmode_db = col_db.reshape(-1, 1)
            self.depth_mm = depth_mm
        else:
            target_h = self.bmode_db.shape[0]
            if col_db.size > target_h:
                col_db = col_db[:target_h]
            elif col_db.size < target_h:
                pad = np.full((target_h - col_db.size,), -self.dr_db, dtype=np.float32)
                col_db = np.concatenate([col_db, pad], axis=0)
            self.bmode_db = np.concatenate([self.bmode_db, col_db.reshape(-1, 1)], axis=1)

        self.lateral_mm.append(float(lateral_mm))
        return self.bmode_db

    def export(self):
        lat = np.array(self.lateral_mm, dtype=np.float32)
        return self.bmode_db, self.depth_mm, lat, float(self.global_env_max)
