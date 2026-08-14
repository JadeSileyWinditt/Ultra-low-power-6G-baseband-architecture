#!/usr/bin/env python3
"""
NUM_TILES scale sweep – prove envelope containment at 64 → 2048 tiles.

Uses the same TBU + prune + memory model as the main harness.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from power.energy_model import EnergyParams
from cosim.harness import run_harness
from tbu.core import TBUParams


def main():
    tile_counts = [64, 256, 512, 1024, 2048]
    print("=" * 72)
    print("NUM_TILES scale sweep – envelope under TBU + memory term")
    print("=" * 72)

    for n in tile_counts:
        energy = EnergyParams(n_tiles=n)
        rows = run_harness(
            load_factors=[0.5, 1.0, 1.5, 2.0],
            energy=energy,
            tbu=TBUParams(S_crit=4.0, delta=0.30, K=12.0),
            include_memory=True,
        )
        peak_ctrl = max(r["controlled_W"] for r in rows)
        peak_unc  = max(r["unconstrained_W"] for r in rows)
        ok = peak_ctrl <= 4.05
        print(f"\n>>> NUM_TILES={n:4d}  unconst_peak={peak_unc:7.2f} W  "
              f"ctrl_peak={peak_ctrl:6.3f} W  envelope_OK={ok}")
        print("-" * 72)

    print("\nScale sweep complete. Hierarchy is parameter-identical at every size.")


if __name__ == "__main__":
    main()
