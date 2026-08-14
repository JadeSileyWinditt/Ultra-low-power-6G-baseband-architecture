//==============================================================================
// polar_encoder.sv – Length-8 Polar encoder stub (rate ~1/2)
//
// Information bits (K=4) are placed on the most reliable synthetic channels
// (bit-reversed positions 3,5,6,7 for N=8).  Remaining positions frozen to 0.
//
// Encoding uses the classical Arikan transform (recursive F⊗n).
// Under approx_en the final XOR stage is truncated (intensity cut visible
// to TBU).  Under skip_noncritical the encoder is bypassed and bits are
// passed through uncoded.
//==============================================================================

`timescale 1ns / 1ps

module polar_encoder #(
  parameter int N = 8,          // code length (must be power of 2)
  parameter int K = 4           // information bits
) (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               approx_en,
  input  logic               skip_noncritical,
  input  logic               in_valid,
  // Packed information bits (K bits).  For N_SC=8 we treat each SC as
  // contributing 1 info bit for simplicity; caller packs them.
  input  logic [K-1:0]       info_bits,

  output logic               out_valid,
  output logic [N-1:0]       coded_bits
);

  // Frozen-bit pattern for N=8, K=4 (reliability order approx)
  // Positions 0,1,2,4 frozen; 3,5,6,7 carry information.
  logic [N-1:0] u;
  always_comb begin
    u = '0;
    u[3] = info_bits[0];
    u[5] = info_bits[1];
    u[6] = info_bits[2];
    u[7] = info_bits[3];
  end

  // Stage-1 (F⊗1)
  logic [N-1:0] s1;
  always_comb begin
    s1[0] = u[0];
    s1[1] = u[0] ^ u[1];
    s1[2] = u[2];
    s1[3] = u[2] ^ u[3];
    s1[4] = u[4];
    s1[5] = u[4] ^ u[5];
    s1[6] = u[6];
    s1[7] = u[6] ^ u[7];
  end

  // Stage-2
  logic [N-1:0] s2;
  always_comb begin
    s2[0] = s1[0];
    s2[1] = s1[1];
    s2[2] = s1[0] ^ s1[2];
    s2[3] = s1[1] ^ s1[3];
    s2[4] = s1[4];
    s2[5] = s1[5];
    s2[6] = s1[4] ^ s1[6];
    s2[7] = s1[5] ^ s1[7];
  end

  // Stage-3 (final)
  logic [N-1:0] s3;
  always_comb begin
    s3[0] = s2[0];
    s3[1] = s2[1];
    s3[2] = s2[2];
    s3[3] = s2[3];
    s3[4] = s2[0] ^ s2[4];
    s3[5] = s2[1] ^ s2[5];
    s3[6] = s2[2] ^ s2[6];
    s3[7] = s2[3] ^ s2[7];
  end

  // Approx / skip path
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      coded_bits <= '0;
      out_valid  <= 1'b0;
    end else if (in_valid) begin
      out_valid <= 1'b1;
      if (skip_noncritical) begin
        // Bypass: just pad info bits
        coded_bits <= { {(N-K){1'b0}}, info_bits };
      end else if (approx_en) begin
        // Truncate the highest stage XORs (intensity reduction)
        coded_bits <= { s3[7:4] & 4'b1100, s3[3:0] };
      end else begin
        coded_bits <= s3;
      end
    end else begin
      out_valid <= 1'b0;
    end
  end

endmodule : polar_encoder
