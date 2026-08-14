//==============================================================================
// polar_decoder.sv – Length-8 Polar successive-cancellation decoder stub
//
// Takes soft LLRs (N of them) and produces hard information bits (K).
// The algorithm is a simplified successive-cancellation tree; under
// approx_en intermediate LLR combinations are truncated, under
// skip_noncritical the decoder is bypassed (hard decisions on the
// first K LLRs).
//
// This keeps the TBU intensity / prune control loop honest while still
// demonstrating a functional channel-coding stage.
//==============================================================================

`timescale 1ns / 1ps

module polar_decoder #(
  parameter int WIDTH = 16,     // LLR bit-width
  parameter int N     = 8,
  parameter int K     = 4
) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       approx_en,
  input  logic                       skip_noncritical,
  input  logic                       in_valid,
  input  logic [WIDTH-1:0]           llr [N],   // channel LLRs

  output logic                       out_valid,
  output logic [K-1:0]               info_bits,
  // Soft reliability of the decoded bits (for optional outer CRC etc.)
  output logic [WIDTH-1:0]           info_llr [K]
);

  //--------------------------------------------------------------------------
  // Simplified SC: treat the four most reliable positions as info
  // and combine LLRs with min-sum style for the frozen checks.
  // Real SC would recurse; this behavioural version exposes the same
  // approx / prune knobs.
  //--------------------------------------------------------------------------
  logic [WIDTH-1:0] l0, l1, l2, l3, l4, l5, l6, l7;
  assign {l0,l1,l2,l3,l4,l5,l6,l7} = {llr[0],llr[1],llr[2],llr[3],
                                      llr[4],llr[5],llr[6],llr[7]};

  // Stage-1 f-node (min-sum approx): L' = sign(L1)*sign(L2)*min(|L1|,|L2|)
  function automatic logic [WIDTH-1:0] f_node(
    input logic [WIDTH-1:0] a, b, input logic approx
  );
    logic [WIDTH-1:0] abs_a, abs_b, m;
    logic sa, sb;
    abs_a = a[WIDTH-1] ? (~a + 1'b1) : a;
    abs_b = b[WIDTH-1] ? (~b + 1'b1) : b;
    m     = (abs_a < abs_b) ? abs_a : abs_b;
    if (approx) m = {m[WIDTH-1:2], 2'b00};   // truncate
    sa = a[WIDTH-1];
    sb = b[WIDTH-1];
    f_node = (sa ^ sb) ? (~m + 1'b1) : m;
  endfunction

  // g-node: L' = L2 + (1-2u)*L1
  function automatic logic [WIDTH-1:0] g_node(
    input logic [WIDTH-1:0] a, b, input logic u, input logic approx
  );
    logic [WIDTH-1:0] term;
    term = u ? (~a + 1'b1) : a;
    g_node = approx ? { (b + term)[WIDTH-1:2], 2'b00 } : (b + term);
  endfunction

  // Very shallow SC tree for N=8 → extract 4 info bits
  logic [WIDTH-1:0] f01, f23, f45, f67;
  logic [WIDTH-1:0] g01, g23, g45, g67;
  logic u0, u1, u2, u3;   // hard decisions on frozen/info

  always_comb begin
    // Level 1
    f01 = f_node(l0, l1, approx_en);
    f23 = f_node(l2, l3, approx_en);
    f45 = f_node(l4, l5, approx_en);
    f67 = f_node(l6, l7, approx_en);

    // Hard decisions on the “left” (frozen-heavy) paths – force 0 for frozen
    u0 = 1'b0;   // frozen
    u1 = 1'b0;   // frozen
    u2 = 1'b0;   // frozen
    // info positions get soft decisions
    u3 = f23[WIDTH-1];   // rough

    // g-nodes for the right half
    g01 = g_node(l0, l1, u0, approx_en);
    g23 = g_node(l2, l3, u3, approx_en);
    g45 = g_node(l4, l5, 1'b0, approx_en);
    g67 = g_node(l6, l7, 1'b0, approx_en);
  end

  // Final info bit extraction (positions 3,5,6,7)
  logic [K-1:0] hard;
  logic [WIDTH-1:0] soft [K];

  always_comb begin
    if (skip_noncritical) begin
      // Bypass: hard decision on first K LLRs
      hard[0] = llr[0][WIDTH-1];
      hard[1] = llr[1][WIDTH-1];
      hard[2] = llr[2][WIDTH-1];
      hard[3] = llr[3][WIDTH-1];
      soft[0] = llr[0]; soft[1] = llr[1];
      soft[2] = llr[2]; soft[3] = llr[3];
    end else begin
      hard[0] = g23[WIDTH-1];          // pos 3
      hard[1] = g45[WIDTH-1];          // pos 5
      hard[2] = g67[WIDTH-1];          // pos 6
      hard[3] = (g67[WIDTH-1] ^ g45[WIDTH-1]); // rough pos 7
      soft[0] = g23;
      soft[1] = g45;
      soft[2] = g67;
      soft[3] = approx_en ? {g67[WIDTH-1:2],2'b00} : g67;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid  <= 1'b0;
      info_bits  <= '0;
      for (int i = 0; i < K; i++) info_llr[i] <= '0;
    end else if (in_valid) begin
      out_valid <= 1'b1;
      info_bits <= hard;
      for (int i = 0; i < K; i++) info_llr[i] <= soft[i];
    end else begin
      out_valid <= 1'b0;
    end
  end

endmodule : polar_decoder
