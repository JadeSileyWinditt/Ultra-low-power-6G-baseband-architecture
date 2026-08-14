//==============================================================================
// phy_tile.sv – Full PHY tile: RX or TX under TBU control
//==============================================================================

`timescale 1ns / 1ps

import tbu_params_pkg::*;

module phy_tile #(
  parameter int TILE_ID       = 0,
  parameter int OPS_WIDTH     = 32,
  parameter int WIDTH         = 16,
  parameter int N_BUTTERFLIES = 4,
  parameter int N_STAGES      = 3,
  parameter int N_SC          = 8
) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic [OPS_WIDTH-1:0]       ops_request,
  input  logic                       ops_valid,
  input  logic [15:0]                throttle_q16,
  input  logic [1:0]                 region_code,
  input  logic                       mode_tx,
  input  logic                       in_valid,
  input  logic [WIDTH-1:0]           in_re  [N_SC],
  input  logic [WIDTH-1:0]           in_im  [N_SC],
  input  logic [1:0]                 bits   [N_SC],
  input  logic [WIDTH-1:0]           tw_re  [N_STAGES][N_BUTTERFLIES],
  input  logic [WIDTH-1:0]           tw_im  [N_STAGES][N_BUTTERFLIES],
  input  logic [WIDTH-1:0]           h_re   [N_SC],
  input  logic [WIDTH-1:0]           h_im   [N_SC],
  output logic [OPS_WIDTH-1:0]       ops_executed,
  output logic                       intensity_cap_hit,
  output logic                       tile_active,
  output logic [1:0]                 prune_level,
  output logic                       out_valid,
  output logic [WIDTH-1:0]           out_re [N_SC],
  output logic [WIDTH-1:0]           out_im [N_SC],
  output logic [WIDTH-1:0]           llr0   [N_SC],
  output logic [WIDTH-1:0]           llr1   [N_SC]
);

  logic [OPS_WIDTH-1:0] ops_grant;
  logic approx_en, skip_noncritical;

  intensity_limiter #(.OPS_WIDTH(OPS_WIDTH)) u_lim (
    .clk(clk), .rst_n(rst_n),
    .ops_request(ops_request), .throttle_q16(throttle_q16),
    .ops_grant(ops_grant), .intensity_cap_hit(intensity_cap_hit)
  );

  pruning_controller u_prune (
    .clk(clk), .rst_n(rst_n),
    .throttle_q16(throttle_q16), .region_code(region_code),
    .approx_en(approx_en), .prune_level(prune_level),
    .skip_noncritical(skip_noncritical)
  );

  logic rx_valid, tx_valid;
  logic [WIDTH-1:0] rx_llr0 [N_SC], rx_llr1 [N_SC];
  logic [WIDTH-1:0] tx_re [N_SC], tx_im [N_SC];

  // Default 2nd-antenna and per-SC 2×2 H for behavioural PHY tile
  logic [WIDTH-1:0] in_re_a1 [N_SC], in_im_a1 [N_SC];
  logic [WIDTH-1:0] h00_re [N_SC], h00_im [N_SC];
  logic [WIDTH-1:0] h01_re [N_SC], h01_im [N_SC];
  logic [WIDTH-1:0] h10_re [N_SC], h10_im [N_SC];
  logic [WIDTH-1:0] h11_re [N_SC], h11_im [N_SC];
  always_comb begin
    for (int i = 0; i < N_SC; i++) begin
      in_re_a1[i] = '0;
      in_im_a1[i] = '0;
      // Near-identity H with mild variation across SCs
      h00_re[i] = 16'h0100 + i[3:0]; h00_im[i] = 16'h0000;
      h01_re[i] = 16'h0010;          h01_im[i] = 16'h0008;
      h10_re[i] = 16'h0008;          h10_im[i] = 16'h0010;
      h11_re[i] = 16'h0100 - i[3:0]; h11_im[i] = 16'h0000;
    end
  end

  rx_chain #(
    .WIDTH(WIDTH), .N_BUTTERFLIES(N_BUTTERFLIES),
    .N_STAGES(N_STAGES), .N_SC(N_SC)
  ) u_rx (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en), .skip_noncritical(skip_noncritical),
    .prune_level(prune_level),
    .in_valid(in_valid & ~mode_tx),
    .in_re(in_re), .in_im(in_im),
    .in_re_a1(in_re_a1), .in_im_a1(in_im_a1),
    .tw_re(tw_re), .tw_im(tw_im),
    .h_re(h_re), .h_im(h_im),
    .h00_re(h00_re), .h00_im(h00_im),
    .h01_re(h01_re), .h01_im(h01_im),
    .h10_re(h10_re), .h10_im(h10_im),
    .h11_re(h11_re), .h11_im(h11_im),
    .out_valid(rx_valid), .llr0(rx_llr0), .llr1(rx_llr1),
    .decoded_bits(), .decode_valid(), .crc_ok()
  );

  tx_chain #(
    .WIDTH(WIDTH), .N_BUTTERFLIES(N_BUTTERFLIES),
    .N_STAGES(N_STAGES), .N_SC(N_SC)
  ) u_tx (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en), .skip_noncritical(skip_noncritical),
    .prune_level(prune_level),
    .in_valid(in_valid & mode_tx),
    .bits(bits), .tw_re(tw_re), .tw_im(tw_im),
    .out_valid(tx_valid), .out_re(tx_re), .out_im(tx_im)
  );

  always_comb begin
    if (mode_tx) begin
      out_valid = tx_valid;
      out_re = tx_re; out_im = tx_im;
      llr0 = '{default:'0}; llr1 = '{default:'0};
    end else begin
      out_valid = rx_valid;
      out_re = '{default:'0}; out_im = '{default:'0};
      llr0 = rx_llr0; llr1 = rx_llr1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ops_executed <= '0; tile_active <= 1'b0;
    end else if (ops_valid) begin
      ops_executed <= ops_grant;
      tile_active  <= (ops_grant != '0);
    end else begin
      ops_executed <= '0; tile_active <= 1'b0;
    end
  end

endmodule : phy_tile
