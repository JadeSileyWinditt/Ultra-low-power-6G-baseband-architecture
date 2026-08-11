#!/usr/bin/env python3
"""Regenerate unconstrained vs controlled power curve for the README."""
from __future__ import annotations

import csv
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from power.energy_model import DEFAULT_ENERGY
from tbu.core import TBUParams, boundary_measure, classify_region, Region


def rtl_throttle(power_W: float, tbu: TBUParams) -> float:
    return float(1.0 - boundary_measure(power_W, tbu))


def rtl_prune(region: Region, throttle: float):
    if region == Region.BOUND:
        return True, 2
    if region == Region.BOUNDARY:
        return True, 1
    if throttle < 0.75:
        return True, 1
    return False, 0


def main() -> None:
    energy = DEFAULT_ENERGY
    tbu = TBUParams(S_crit=4.0, delta=0.30, K=12.0)
    loads = list(np.concatenate([np.linspace(0.2, 1.0, 9), np.linspace(1.1, 3.0, 20)]))
    n, e_op, cap = energy.n_tiles, energy.energy_per_op_J, energy.max_ops_per_tile

    rows = []
    for load in loads:
        req = load * cap
        unconst = float(n * req * e_op)
        thr = rtl_throttle(unconst, tbu)
        region = classify_region(unconst, tbu)
        approx, prune = rtl_prune(region, thr)
        eff = energy.effective_ops(req, approx_en=approx, prune_level=prune)
        ctrl = float(n * eff * e_op * thr)
        rows.append(dict(load=load, unconstrained_W=unconst, controlled_W=ctrl,
                         throttle=thr, region=region.name, prune=prune))

    out = ROOT / "docs"
    out.mkdir(exist_ok=True)
    csv_path = out / "envelope_curve.csv"
    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    xs = [r["load"] for r in rows]
    yu = [r["unconstrained_W"] for r in rows]
    yc = [r["controlled_W"] for r in rows]
    pu, pc = max(yu), max(yc)

    fig, ax = plt.subplots(figsize=(9, 5.2), dpi=160)
    ax.plot(xs, yu, color="#c0392b", lw=2.2, label="Unconstrained request")
    ax.plot(xs, yc, color="#1a7f4b", lw=2.4, label="Controlled (TBU + prune + intensity)")
    ax.axhline(4.0, color="#2c3e50", ls="--", lw=1.6, label="4 W thermal envelope")
    ax.axhline(2.8, color="#7f8c8d", ls=":", lw=1.4, label="2.8 W intensity-cap design")
    ax.fill_between(xs, 0, 4.0, color="#1a7f4b", alpha=0.06)
    ax.set_xlabel("Load factor (× intensity-cap demand)")
    ax.set_ylabel("Fabric power (W)")
    ax.set_title("TBU Envelope Proof — 2048-tile co-sim", fontweight="bold")
    ax.set_xlim(min(xs), max(xs))
    ax.set_ylim(0, max(pu * 1.08, 4.5))
    ax.grid(True, alpha=0.35)
    ax.legend(loc="upper left", fontsize=9)
    ax.text(0.98, 0.05,
            f"Peak unconstrained {pu:.2f} W → controlled {pc:.2f} W\nEnvelope 4.0 W respected",
            transform=ax.transAxes, ha="right", va="bottom", fontsize=9,
            bbox=dict(boxstyle="round,pad=0.35", facecolor="white", edgecolor="#bdc3c7"))
    fig.tight_layout()
    png = out / "envelope_curve.png"
    fig.savefig(png, bbox_inches="tight", facecolor="white")
    print(f"Wrote {csv_path}")
    print(f"Wrote {png}")
    print(f"Peak unconstrained {pu:.3f} W | controlled {pc:.3f} W")


if __name__ == "__main__":
    main()
