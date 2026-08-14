"""
Calibrated energy / power model for the 2048-tile TBU baseband fabric.

Source numbers (architecture specification):
  - ~40 billion transistors total
  - ≤ 700 ops / transistor (local intensity hard-cap)
  - ~0.10 pJ / compute operation
  - Memory access cost (SRAM / local buffer) modelled separately
  - ≤ 4 W thermal envelope
  - Peak useful workload ≤ 2.6 × 10¹³ ops/s after pruning

Scope note
----------
The original 12–15× intensity claim is compute-side only.  Memory-bound
phases see less reduction.  With the memory term enabled the end-to-end
energy benefit under realistic traffic typically lands nearer 1.5–3×,
while the hard thermal claim (≤ 4 W under TBU control) remains the
primary architectural guarantee.
"""

from __future__ import annotations

from dataclasses import dataclass
import numpy as np


@dataclass(frozen=True)
class EnergyParams:
    n_tiles: int = 2048
    transistors_total: int = 40_000_000_000
    intensity_cap_ops_per_transistor: float = 700.0
    energy_per_op_J: float = 0.10e-12          # 0.10 pJ compute
    thermal_envelope_W: float = 4.0
    target_ops_per_s: float = 2.6e13           # after 12–15× intensity cut

    # Approx / prune intensity reduction factors (compute path)
    approx_factor: float = 0.55                  # approx ALU activity vs exact
    prune_light_factor: float = 0.75
    prune_aggressive_factor: float = 0.40

    # ------------------------------------------------------------------
    # Memory energy term
    # ------------------------------------------------------------------
    energy_per_mem_access_J: float = 1.5e-12   # 1.5 pJ
    mem_access_fraction: float = 0.30
    mem_prune_light_factor: float = 0.85
    mem_prune_aggressive_factor: float = 0.55
    mem_approx_factor: float = 0.90

    @property
    def transistors_per_tile(self) -> float:
        return self.transistors_total / self.n_tiles

    @property
    def max_ops_per_tile(self) -> float:
        return self.transistors_per_tile * self.intensity_cap_ops_per_transistor

    @property
    def max_ops_fabric(self) -> float:
        return self.max_ops_per_tile * self.n_tiles

    @property
    def power_at_full_intensity_W(self) -> float:
        """Unconstrained power if every tile ran at the intensity cap (compute only)."""
        return self.max_ops_fabric * self.energy_per_op_J

    @property
    def power_at_full_with_mem_W(self) -> float:
        """Design-point power including memory term at full intensity."""
        compute = self.max_ops_fabric * self.energy_per_op_J
        mem = self.max_ops_fabric * self.mem_access_fraction * self.energy_per_mem_access_J
        return compute + mem

    def effective_ops(
        self,
        requested_ops: float,
        approx_en: bool = False,
        prune_level: int = 0,
    ) -> float:
        """
        Apply algorithmic intensity reduction then clamp to the hard cap.
        prune_level: 0=none, 1=light, 2=aggressive
        """
        ops = requested_ops
        if prune_level == 1:
            ops *= self.prune_light_factor
        elif prune_level >= 2:
            ops *= self.prune_aggressive_factor
        if approx_en:
            ops *= self.approx_factor
        return min(ops, self.max_ops_per_tile)

    def effective_mem_accesses(
        self,
        requested_ops: float,
        approx_en: bool = False,
        prune_level: int = 0,
    ) -> float:
        """Memory accesses after prune / approx reduction."""
        mem = requested_ops * self.mem_access_fraction
        if prune_level == 1:
            mem *= self.mem_prune_light_factor
        elif prune_level >= 2:
            mem *= self.mem_prune_aggressive_factor
        if approx_en:
            mem *= self.mem_approx_factor
        return min(mem, self.max_ops_per_tile * self.mem_access_fraction)

    def power_W(
        self,
        ops_per_tile: float | np.ndarray,
        throttle: float = 1.0,
        include_memory: bool = True,
        approx_en: bool = False,
        prune_level: int = 0,
    ) -> float | np.ndarray:
        """Instantaneous power for one or many tiles after throttle."""
        ops = np.asarray(ops_per_tile, dtype=float)
        compute_p = ops * self.energy_per_op_J * throttle

        if not include_memory:
            return compute_p

        mem = self.effective_mem_accesses(
            float(np.mean(ops)) if ops.ndim else float(ops),
            approx_en=approx_en,
            prune_level=prune_level,
        )
        if ops.ndim:
            scale = ops / (np.mean(ops) + 1e-30)
            mem_p = scale * mem * self.energy_per_mem_access_J * throttle
        else:
            mem_p = mem * self.energy_per_mem_access_J * throttle

        return compute_p + mem_p

    def fabric_power_W(
        self,
        requested_ops_per_tile: float,
        throttle: float = 1.0,
        approx_en: bool = False,
        prune_level: int = 0,
        include_memory: bool = True,
    ) -> tuple[float, float, float]:
        """Return (compute_W, mem_W, total_W) for the whole fabric."""
        eff_ops = self.effective_ops(
            requested_ops_per_tile, approx_en=approx_en, prune_level=prune_level
        )
        compute = self.n_tiles * eff_ops * self.energy_per_op_J * throttle

        mem_acc = self.effective_mem_accesses(
            requested_ops_per_tile, approx_en=approx_en, prune_level=prune_level
        )
        mem = self.n_tiles * mem_acc * self.energy_per_mem_access_J * throttle

        total = compute + (mem if include_memory else 0.0)
        return compute, mem, total

    def summary(self) -> str:
        return (
            f"Energy model\n"
            f"  Tiles              : {self.n_tiles}\n"
            f"  Transistors/tile   : {self.transistors_per_tile:,.0f}\n"
            f"  Intensity cap      : {self.intensity_cap_ops_per_transistor} ops/xtor\n"
            f"  Energy/op (compute): {self.energy_per_op_J*1e12:.2f} pJ\n"
            f"  Energy/mem access  : {self.energy_per_mem_access_J*1e12:.2f} pJ\n"
            f"  Mem access fraction: {self.mem_access_fraction:.0%}\n"
            f"  Power @ full (comp): {self.power_at_full_intensity_W:.3f} W\n"
            f"  Power @ full (+mem): {self.power_at_full_with_mem_W:.3f} W\n"
            f"  Thermal envelope   : {self.thermal_envelope_W} W\n"
            f"  Target ops/s       : {self.target_ops_per_s:.2e}\n"
        )


DEFAULT_ENERGY = EnergyParams()

KERNEL_PROFILES = {
    "fft_heavy": EnergyParams(
        mem_access_fraction=0.18,
        energy_per_mem_access_J=1.2e-12,
    ),
    "mimo_eq": EnergyParams(
        mem_access_fraction=0.28,
        energy_per_mem_access_J=1.5e-12,
    ),
    "coding": EnergyParams(
        mem_access_fraction=0.38,
        energy_per_mem_access_J=1.8e-12,
    ),
    "balanced": DEFAULT_ENERGY,
}


if __name__ == "__main__":
    e = DEFAULT_ENERGY
    print(e.summary())
    print(f"Effective ops (exact, no prune) : {e.effective_ops(1e10):.3e}")
    print(f"Effective ops (approx+aggr)     : {e.effective_ops(1e10, approx_en=True, prune_level=2):.3e}")
    c, m, t = e.fabric_power_W(1e10, throttle=1.0, approx_en=True, prune_level=2)
    print(f"Fabric power (approx+aggr)      : compute={c:.3f} W  mem={m:.3f} W  total={t:.3f} W")
    print("\nKernel profiles (full-intensity design power):")
    for name, p in KERNEL_PROFILES.items():
        print(f"  {name:12s}  mem_frac={p.mem_access_fraction:.0%}  "
              f"P_full={p.power_at_full_with_mem_W:.2f} W")
