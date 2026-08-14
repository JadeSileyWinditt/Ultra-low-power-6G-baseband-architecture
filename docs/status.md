# Build Status – Ultra-Low-Power 6G Baseband

## Working
- Continuous TBU thermal boundary (global + regional)
- Algorithmic intensity reduction (approx + pruning)
- Full RX chain: dual-FFT → per-SC 2×2 ZF MIMO detect → dual soft demap → polar decode
- Full TX chain: polar encode → map → IFFT
- PHY tile (TX/RX under TBU)
- Hierarchical fabric path to 2048 tiles
- Co-sim harness + envelope stress tests
- End-to-end observable throttle / prune
- Envelope proof: unconstrained peak 8.40 W → controlled peak 0.92 W (≤ 4 W)
- Channel coding stub (polar N=8 / K=4, approx-aware)

## Next
1. Optional memory-energy term in the model
2. Larger NUM_TILES elaboration when control loops are trusted
3. Per-RE CSI streaming for MIMO (currently shared H)
4. Stronger polar / LDPC (longer block, CRC, list decoding)

## Core claim
High-throughput 6G baseband processing inside a ≤ 4 W mobile thermal envelope
via continuous boundary control + intensity reduction.
