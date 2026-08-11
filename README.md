# Ultra-Low-Power 6G Baseband Architecture

**2048-Tile Fabric • Sub-THz Target • ≤ 4 W Envelope • Continuous TBU Control**

## Envelope proof (co-sim, 2048 tiles)

| Metric | Value |
|--------|--------|
| Unconstrained over-subscription peak | **8.4 W** |
| Controlled peak (TBU + prune + intensity) | **0.92 W** |
| Thermal envelope | **4.0 W — respected** |
| Intensity-cap design power | **2.8 W** |

```bash
bash scripts/run_envelope_demo.sh
# or: PYTHONPATH=python python3 python/cosim/harness.py

## Core Idea

Two cooperating loops:

1. **Thermal containment (TBU / TBCU)**  
   Total power is treated as an action potential. A continuous boundary measure generates throttle factors that keep the fabric near or under **4 W**.

2. **Algorithmic intensity reduction**  
   Under thermal pressure the fabric increases approximate arithmetic and pruning, cutting effective operations (the 12–15× intensity path).

Together they form a closed control system: load rises → power approaches the envelope → throttle + pruning increase → intensity drops → fabric stays inside budget.

---

## What is implemented

| Layer | Blocks |
|-------|--------|
| **Theory** | Topological Boundary Unit mathematics (`python/tbu/`) |
| **Energy** | Calibrated model – 0.10 pJ/op, intensity caps, envelope (`python/power/`) |
| **Thermal RTL** | TBCU, regional TBCU, multi-cycle power reduce |
| **Intensity RTL** | Approx ALU, pruning controller |
| **Kernels** | FFT butterfly, OFDM FFT stage |
| **Tiles** | Compute tile, DSP tile |
| **Hierarchy** | Fabric slice → multi-slice top → configurable full fabric (`NUM_TILES` up to 2048) |
| **NoC** | Hierarchical address map + skeleton |
| **Safety** | Assertion package + bind example |
| **Proof** | Co-sim harness + envelope stress testbench |
| **Docs** | TBU mapping + 2048-tile elaboration plan |

---

## Quick start (software proof)

```bash
cd python

PYTHONPATH=. python3 cosim/harness.py
python/
  tbu/           continuous boundary mathematics
  power/         calibrated energy model + fabric power model
  cosim/         software twin / envelope harness
rtl/
  common/        parameters + assertions
  tile/          compute tile, DSP tile, intensity limiter, approx ALU
  tbc/           TBCU, regional TBCU, power reduce
  kernels/       FFT butterfly, OFDM stage
  optim/         pruning controller
  noc/           address map + hierarchical skeleton
  top/           slice, multi-slice, full configurable fabric
sim/             directed + stress testbenches
docs/            TBU framework + elaboration plan

Status
Working hierarchical RTL + software twin demonstrating the closed thermal/intensity control loop.

Full 2048-tile elaboration, deeper OFDM pipelines, and silicon power sign-off modelling are the next engineering steps.

Citation
Jade Siley-Winditt – Ultra-Low-Power 6G Baseband Architecture (2048-tile fabric, ≤ 4 W)
Jade Siley-Winditt – The Topological Boundary Unit (TBU): A Unified Mathematical Framework for Boundary-State Dynamics (2026)

License
Copyright © 2026 Jade Siley-Winditt. All rights reserved.
Research and educational use only. No commercial use, reproduction, modification, or silicon fabrication without prior written permission.
