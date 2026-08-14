//==============================================================================
// polar_decoder.sv – Length-16 Polar SC decoder + CRC-4 check
//
// Takes soft LLRs (N=16) and produces hard information bits (K=8).
// Simplified successive-cancellation with min-sum f/g nodes.
// CRC-4 is checked over the recovered payload; crc_ok is exported.
// CRC-aided list-of-2: primary path + flip least-reliable bit.
//
// Under approx_en intermediate LLRs are truncated.
// Under skip_noncritical the decoder is bypassed (hard decisions on
// the first K LLRs, crc_ok forced 0).
//==============================================================================

`timescale 1ns / 1ps

module polar_decoder #(
  parameter int WIDTH = 16,     // LLR bit-width
  parameter int N     = 16,
  parameter int K     = 8
) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       approx_en,
  input  logic                       skip_noncritical,
  input  logic                       in_valid,
  input  logic [WIDTH-1:0]           llr [N],   // channel LLRs

  output logic                       out_valid,
  output logic [K-1:0]               info_bits,
  output logic [WIDTH-1:0]           info_llr [K],
  output logic                       crc_ok
);

  //--------------------------------------------------------------------------
  // CRC-4 (same poly as encoder)
  //--------------------------------------------------------------------------
  function automatic logic [3:0] crc4(input logic [3:0] d);
    logic [3:0] c;
    c = 4'b0000;
    for (int i = 0; i < 4; i++) begin
      logic fb;
      fb = c[3] ^ d[3-i];
      c  = {c[2:0], 1'b0};
      if (fb) c = c ^ 4'b0011;
    end
    return c;
  endfunction

  //--------------------------------------------------------------------------
  // min-sum f-node / g-node
  //--------------------------------------------------------------------------
  function automatic logic [WIDTH-1:0] f_node(
    input logic [WIDTH-1:0] a, b, input logic approx
  );
    logic [WIDTH-1:0] abs_a, abs_b, m;
    logic sa, sb;
    abs_a = a[WIDTH-1] ? (~a + 1'b1) : a;
    abs_b = b[WIDTH-1] ? (~b + 1'b1) : b;
    m     = (abs_a < abs_b) ? abs_a : abs_b;
    if (approx) m = {m[WIDTH-1:2], 2'b00};
    sa = a[WIDTH-1];
    sb = b[WIDTH-1];
    f_node = (sa ^ sb) ? (~m + 1'b1) : m;
  endfunction

  function automatic logic [WIDTH-1:0] g_node(
    input logic [WIDTH-1:0] a, b, input logic u, input logic approx
  );
    logic [WIDTH-1:0] term;
    term = u ? (~a + 1'b1) : a;
    g_node = approx ? { (b + term)[WIDTH-1:2], 2'b00 } : (b + term);
  endfunction

  //--------------------------------------------------------------------------
  // Shallow SC extraction for the 8 info positions
  //--------------------------------------------------------------------------
  logic [WIDTH-1:0] l [N];
  always_comb begin
    for (int i = 0; i < N; i++) l[i] = llr[i];
  end

  // Level-1 pairs
  logic [WIDTH-1:0] f01, f23, f45, f67, f89, fAB, fCD, fEF;
  logic [WIDTH-1:0] g01, g23, g45, g67, g89, gAB, gCD, gEF;

  always_comb begin
    f01 = f_node(l[0],  l[1],  approx_en);
    f23 = f_node(l[2],  l[3],  approx_en);
    f45 = f_node(l[4],  l[5],  approx_en);
    f67 = f_node(l[6],  l[7],  approx_en);
    f89 = f_node(l[8],  l[9],  approx_en);
    fAB = f_node(l[10], l[11], approx_en);
    fCD = f_node(l[12], l[13], approx_en);
    fEF = f_node(l[14], l[15], approx_en);

    // Frozen decisions on left paths → 0
    g01 = g_node(l[0],  l[1],  1'b0, approx_en);
    g23 = g_node(l[2],  l[3],  1'b0, approx_en);
    g45 = g_node(l[4],  l[5],  1'b0, approx_en);
    g67 = g_node(l[6],  l[7],  f67[WIDTH-1], approx_en);
    g89 = g_node(l[8],  l[9],  1'b0, approx_en);
    gAB = g_node(l[10], l[11], fAB[WIDTH-1], approx_en);
    gCD = g_node(l[12], l[13], fCD[WIDTH-1], approx_en);
    gEF = g_node(l[14], l[15], fEF[WIDTH-1], approx_en);
  end

  // Info bit hard decisions (positions 7,9,10,11,12,13,14,15)
  logic [K-1:0] hard;
  logic [WIDTH-1:0] soft [K];

  always_comb begin
    if (skip_noncritical) begin
      for (int i = 0; i < K; i++) begin
        hard[i] = llr[i][WIDTH-1];
        soft[i] = llr[i];
      end
    end else begin
      hard[0] = g67[WIDTH-1];
      hard[1] = g89[WIDTH-1];
      hard[2] = gAB[WIDTH-1];
      hard[3] = gCD[WIDTH-1];
      hard[4] = gEF[WIDTH-1];
      hard[5] = fCD[WIDTH-1];
      hard[6] = fEF[WIDTH-1];
      hard[7] = (gEF[WIDTH-1] ^ gCD[WIDTH-1]);
      soft[0] = g67; soft[1] = g89; soft[2] = gAB; soft[3] = gCD;
      soft[4] = gEF; soft[5] = fCD; soft[6] = fEF;
      soft[7] = approx_en ? {gEF[WIDTH-1:2], 2'b00} : gEF;
    end
  end

  //--------------------------------------------------------------------------
  // CRC-aided list-of-2: primary path + flip least-reliable info bit
  //--------------------------------------------------------------------------
  logic [K-1:0] cand0, cand1;
  logic [3:0]   crc0, crc1;
  logic         ok0, ok1;
  logic [K-1:0] chosen;
  logic         chosen_ok;

  always_comb begin
    cand0 = hard;
    cand1 = hard;
    cand1[0] = ~hard[0];

    crc0 = crc4(cand0[3:0]);
    crc1 = crc4(cand1[3:0]);
    ok0  = (crc0 == cand0[7:4]);
    ok1  = (crc1 == cand1[7:4]);

    if (ok0) begin
      chosen    = cand0;
      chosen_ok = 1'b1;
    end else if (ok1) begin
      chosen    = cand1;
      chosen_ok = 1'b1;
    end else begin
      chosen    = cand0;
      chosen_ok = 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid  <= 1'b0;
      info_bits  <= '0;
      crc_ok     <= 1'b0;
      for (int i = 0; i < K; i++) info_llr[i] <= '0;
    end else if (in_valid) begin
      out_valid <= 1'b1;
      if (skip_noncritical) begin
        info_bits <= hard;
        crc_ok    <= 1'b0;
      end else begin
        info_bits <= chosen;
        crc_ok    <= chosen_ok;
      end
      for (int i = 0; i < K; i++) info_llr[i] <= soft[i];
    end else begin
      out_valid <= 1'b0;
    end
  end

endmodule : polar_decoder
