#!/usr/bin/env python3
"""
Co-simulation harness – fabric-wide ≤4 W envelope proof.

Mirrors RTL policy:
  - inverted logistic throttle (TBCU)
  - pruning levels (pruning_controller)
  - intensity hard-cap + approx factor (energy_model)
  - optional memory-energy term (SRAM / buffer accesses)

Power is computed over the full tile fabric
(n_tiles × (compute ops + mem accesses) × energy).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import numpy as np
from power.energy_model import EnergyParams, DEFAULT_ENERGY
from tbu.core import TBUParams, boundary_measure, classify_region, Region


def rtl_throttle(power_W: float, tbu: TBUParams) -> float:
    """1 - B_δ(P) → high power produces strong containment."""
    return float(1.0 - boundary_measure(power_W, tbu))


def rtl_prune(region: Region, throttle: float) -> tuple[bool, int]:
    if region == Region.BOUND:
        return True, 2
    if region == Region.BOUNDARY:
        return True, 1
    if throttle < 0.75:
        return True, 1
    return False, 0


def run_harness(
    load_factors: list[float] | None = None,
    energy: EnergyParams = DEFAULT_ENERGY,
    tbu: TBUParams = TBUParams(S_crit=4.0, delta=0.30, K=12.0),
    include_memory: bool = True,
) -> list[dict]:
    if load_factors is None:
        # Design point → over-subscribe past envelope → cool-down
        load_factors = list(np.concatenate([
            np.linspace(0.2, 1.0, 5),
            np.linspace(1.2, 3.0, 10),
            np.linspace(1.0, 0.3, 4),
        ]))

    n = energy.n_tiles
    cap_tile = energy.max_ops_per_tile

    print("=" * 80)
    print("TBU Co-simulation – Fabric Envelope Proof (2048 tiles)")
    if include_memory:
        print("  (compute + memory energy term enabled)")
    else:
        print("  (compute-only)")
    print("=" * 80)
    print(energy.summary())
    print(f"TBU  S_crit={tbu.S_crit} W   δ={tbu.delta} W")
    print()
    print(f"{'Load':>6} {'Unconst W':>10} {'Ctrl W':>8} {'Mem W':>7} "
          f"{'Thr':>6} {'Region':<10} {'Prune':>5} {'OK':>4}")
    print("-" * 80)

    rows: list[dict] = []
    peak_ctrl = 0.0
    peak_unconst = 0.0

    for load in load_factors:
        req_tile = load * cap_tile

        # Unconstrained (compute + memory, no throttle / prune)
        _, _, unconst = energy.fabric_power_W(
            req_tile, throttle=1.0, approx_en=False, prune_level=0,
            include_memory=include_memory,
        )
        peak_unconst = max(peak_unconst, unconst)

        # First-pass region classification still uses unconstrained power
        thr = rtl_throttle(unconst, tbu)
        region = classify_region(unconst, tbu)
        approx_en, prune_level = rtl_prune(region, thr)

        # Controlled path
        comp_w, mem_w, ctrl = energy.fabric_power_W(
            req_tile,
            throttle=thr,
            approx_en=approx_en,
            prune_level=prune_level,
            include_memory=include_memory,
        )
        peak_ctrl = max(peak_ctrl, ctrl)
        ok = ctrl <= energy.thermal_envelope_W + 0.05

        print(f"{load:6.2f} {unconst:10.3f} {ctrl:8.3f} {mem_w:7.3f} "
              f"{thr:6.3f} {region.name:<10} {prune_level:5d} "
              f"{'YES' if ok else 'NO':>4}")

        rows.append({
            "load": load,
            "unconstrained_W": unconst,
            "controlled_W": ctrl,
            "mem_W": mem_w,
            "compute_W": comp_w,
            "throttle": thr,
            "region": region.name,
            "prune": prune_level,
            "ok": ok,
        })

    print("-" * 80)
    print(f"Peak unconstrained power : {peak_unconst:.3f} W")
    print(f"Peak controlled power    : {peak_ctrl:.3f} W")
    print(f"Thermal envelope         : {energy.thermal_envelope_W:.3f} W")
    print(f"Headroom under envelope  : {energy.thermal_envelope_W - peak_ctrl:.3f} W")
    print(f"Envelope respected       : "
          f"{'YES' if peak_ctrl <= energy.thermal_envelope_W + 0.05 else 'NO'}")
    print(f"Design power (comp only) : {energy.power_at_full_intensity_W:.3f} W")
    print(f"Design power (comp+mem)  : {energy.power_at_full_with_mem_W:.3f} W")
    print("=" * 80)
    return rows


if __name__ == "__main__":
    run_harness(include_memory=True)
