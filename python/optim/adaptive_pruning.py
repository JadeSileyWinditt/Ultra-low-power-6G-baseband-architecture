"""Adaptive Pruning Controller v2 – history-aware intensity reduction."""
from __future__ import annotations
from collections import deque
from dataclasses import dataclass
from enum import IntEnum
from typing import Deque, Tuple
import numpy as np

class PruneLevel(IntEnum):
    NONE = 0
    LIGHT = 1
    AGGRESSIVE = 2

@dataclass(frozen=True)
class PruneDecision:
    approx_en: bool
    prune_level: int
    skip_noncritical: bool
    pressure: float

class AdaptivePruningController:
    def __init__(self, window: int = 8, hyst: float = 0.08):
        self.window = max(3, window)
        self.hyst = hyst
        self._hist: Deque[Tuple[float, float, float]] = deque(maxlen=self.window)
        self._last_pressure = 0.0
        self._last_decision = PruneDecision(False, 0, False, 0.0)

    def reset(self) -> None:
        self._hist.clear()
        self._last_pressure = 0.0
        self._last_decision = PruneDecision(False, 0, False, 0.0)

    def observe(self, boundary_measure: float, entropy: float, throttle: float) -> PruneDecision:
        B = float(np.clip(boundary_measure, 0.0, 1.0))
        H = float(np.clip(entropy, 0.0, np.log(2)))
        thr = float(np.clip(throttle, 0.0, 1.0))
        self._hist.append((B, H, thr))
        if len(self._hist) < 2:
            pressure = B * 0.6 + (1.0 - thr) * 0.4
        else:
            _, Hs, thrs = zip(*self._hist)
            peak_H = max(Hs)
            mean_undershoot = 1.0 - float(np.mean(thrs))
            pressure = 0.45 * B + 0.30 * (peak_H / np.log(2)) + 0.25 * mean_undershoot
        p = pressure
        if abs(p - self._last_pressure) < self.hyst:
            decision = self._last_decision
        else:
            if p < 0.25:
                decision = PruneDecision(False, PruneLevel.NONE, False, p)
            elif p < 0.55:
                decision = PruneDecision(True, PruneLevel.LIGHT, False, p)
            else:
                decision = PruneDecision(True, PruneLevel.AGGRESSIVE, True, p)
        self._last_pressure = p
        self._last_decision = decision
        return decision
