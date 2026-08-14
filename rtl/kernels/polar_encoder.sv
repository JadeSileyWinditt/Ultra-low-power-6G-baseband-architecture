//==============================================================================
// polar_encoder.sv – Length-16 Polar encoder + CRC-4 (rate ~1/2)
//
// Information bits (K=8) include a 4-bit CRC over the first 4 payload bits.
// Frozen-bit pattern places info on the more reliable synthetic channels.
//
// Encoding uses the classical Arikan transform (F⊗4).
// Under approx_en the highest-stage XORs are truncated (intensity cut).
// Under skip_noncritical the encoder is bypassed (uncoded + zero pad).
//==============================================================================

`timescale 1ns / 1ps

module polar_encoder #(
  parameter int N = 16,         // code length (power of 2)
  parameter int K = 8           // information bits (incl. CRC)
) (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               approx_en,
  input  logic               skip_noncritical,
  input  logic               in_valid,
  input  logic [K-1:0]       info_bits,   // [7:4]=CRC, [3:0]=payload (or caller packs)

  output logic               out_valid,
  output logic [N-1:0]       coded_bits
);

  //--------------------------------------------------------------------------
  // Simple CRC-4 (poly x^4 + x + 1) over the lower 4 bits
  //--------------------------------------------------------------------------
  function automatic logic [3:0] crc4(input logic [3:0] d);
    logic [3:0] c;
    c = 4'b0000;
    for (int i = 0; i < 4; i++) begin
      logic fb;
      fb = c[3] ^ d[3-i];
      c  = {c[2:0], 1'b0};
      if (fb) c = c ^ 4'b0011;   // x+1
    end
    return c;
  endfunction

  logic [K-1:0] info_crc;
  always_comb begin
    info_crc[3:0] = info_bits[3:0];
    info_crc[7:4] = crc4(info_bits[3:0]);
  end

  //--------------------------------------------------------------------------
  // Bit placement (N=16, K=8) – higher indices ≈ more reliable
  // Info positions: 7,9,10,11,12,13,14,15
  //--------------------------------------------------------------------------
  logic [N-1:0] u;
  always_comb begin
    u = '0;
    u[7]  = info_crc[0];
    u[9]  = info_crc[1];
    u[10] = info_crc[2];
    u[11] = info_crc[3];
    u[12] = info_crc[4];
    u[13] = info_crc[5];
    u[14] = info_crc[6];
    u[15] = info_crc[7];
  end

  //--------------------------------------------------------------------------
  // Arikan F⊗4 – 4 stages of butterfly XOR
  //--------------------------------------------------------------------------
  logic [N-1:0] s0, s1, s2, s3, s4;
  assign s0 = u;

  // Stage 1 (distance 1)
  always_comb begin
    for (int i = 0; i < N; i += 2) begin
      s1[i]   = s0[i];
      s1[i+1] = s0[i] ^ s0[i+1];
    end
  end

  // Stage 2 (distance 2)
  always_comb begin
    for (int i = 0; i < N; i += 4) begin
      s2[i]   = s1[i];
      s2[i+1] = s1[i+1];
      s2[i+2] = s1[i]   ^ s1[i+2];
      s2[i+3] = s1[i+1] ^ s1[i+3];
    end
  end

  // Stage 3 (distance 4)
  always_comb begin
    for (int i = 0; i < N; i += 8) begin
      s3[i]   = s2[i];
      s3[i+1] = s2[i+1];
      s3[i+2] = s2[i+2];
      s3[i+3] = s2[i+3];
      s3[i+4] = s2[i]   ^ s2[i+4];
      s3[i+5] = s2[i+1] ^ s2[i+5];
      s3[i+6] = s2[i+2] ^ s2[i+6];
      s3[i+7] = s2[i+3] ^ s2[i+7];
    end
  end

  // Stage 4 (distance 8)
  always_comb begin
    for (int i = 0; i < 8; i++) begin
      s4[i]   = s3[i];
      s4[i+8] = s3[i] ^ s3[i+8];
    end
  end

  //--------------------------------------------------------------------------
  // Approx / skip path
  //--------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      coded_bits <= '0;
      out_valid  <= 1'b0;
    end else if (in_valid) begin
      out_valid <= 1'b1;
      if (skip_noncritical) begin
        coded_bits <= { {(N-K){1'b0}}, info_crc };
      end else if (approx_en) begin
        // Truncate highest-stage XORs (intensity reduction)
        coded_bits <= { s4[15:8] & 8'hF0, s4[7:0] };
      end else begin
        coded_bits <= s4;
      end
    end else begin
      out_valid <= 1'b0;
    end
  end

endmodule : polar_encoder
