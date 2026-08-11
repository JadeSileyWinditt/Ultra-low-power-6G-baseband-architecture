//==============================================================================
// rx_chain.sv – OFDM receive path with MIMO
//
//   time-domain → FFT pipeline → channel EQ → 2x2 MIMO detect → soft demap
//
// All stages respect TBU pruning / approx_en.
//==============================================================================

`timescale 1ns / 1ps

module rx_chain #(
  parameter int WIDTH         = 16,
  parameter int N_BUTTERFLIES = 4,
  parameter int N_STAGES      = 3,
  parameter int N_SC          = 8
) (
  input  logic                       clk,
  input  logic                       rst_n,

  input  logic                       approx_en,
  input  logic                       skip_noncritical,
  input  logic [1:0]                 prune_level,

  input  logic                       in_valid,
  input  logic [WIDTH-1:0]           in_re  [N_SC],
  input  logic [WIDTH-1:0]           in_im  [N_SC],
  input  logic [WIDTH-1:0]           tw_re  [N_STAGES][N_BUTTERFLIES],
  input  logic [WIDTH-1:0]           tw_im  [N_STAGES][N_BUTTERFLIES],

  // Per-subcarrier channel (stream 0 path uses h_*; MIMO uses full 2x2 below)
  input  logic [WIDTH-1:0]           h_re   [N_SC],
  input  logic [WIDTH-1:0]           h_im   [N_SC],

  // Optional 2nd antenna time-domain input (if unused, tie to 0)
  input  logic [WIDTH-1:0]           in_re_a1 [N_SC],
  input  logic [WIDTH-1:0]           in_im_a1 [N_SC],

  // 2x2 channel for MIMO (per RE – simplified: one shared H for stub scale)
  input  logic [WIDTH-1:0]           h00_re, h00_im, h01_re, h01_im,
  input  logic [WIDTH-1:0]           h10_re, h10_im, h11_re, h11_im,

  output logic                       out_valid,
  output logic [WIDTH-1:0]           llr0   [N_SC],
  output logic [WIDTH-1:0]           llr1   [N_SC]
);

  //--------------------------------------------------------------------------
  // FFT → EQ (symbol_chain) on antenna 0
  //--------------------------------------------------------------------------
  logic                 sym_valid;
  logic [WIDTH-1:0]     x_re [N_SC];
  logic [WIDTH-1:0]     x_im [N_SC];

  symbol_chain #(
    .WIDTH(WIDTH), .N_BUTTERFLIES(N_BUTTERFLIES),
    .N_STAGES(N_STAGES), .N_SC(N_SC)
  ) u_symbol (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en),
    .skip_noncritical(skip_noncritical),
    .prune_level(prune_level),
    .in_valid(in_valid),
    .in_re(in_re), .in_im(in_im),
    .tw_re(tw_re), .tw_im(tw_im),
    .h_re(h_re), .h_im(h_im),
    .out_valid(sym_valid),
    .x_re(x_re), .x_im(x_im)
  );

  //--------------------------------------------------------------------------
  // MIMO detect on first resource element pair (behavioural scale)
  // Full per-SC MIMO array can be generated later.
  //--------------------------------------------------------------------------
  logic                 mimo_valid;
  logic [WIDTH-1:0]     m0_re, m0_im, m1_re, m1_im;

  logic mimo_fire;
  assign mimo_fire = sym_valid & ~skip_noncritical;

  mimo_detect #(.WIDTH(WIDTH)) u_mimo (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en),
    .in_valid(mimo_fire),
    .y0_re(x_re[0]), .y0_im(x_im[0]),
    .y1_re(x_re[1]), .y1_im(x_im[1]),
    .h00_re(h00_re), .h00_im(h00_im),
    .h01_re(h01_re), .h01_im(h01_im),
    .h10_re(h10_re), .h10_im(h10_im),
    .h11_re(h11_re), .h11_im(h11_im),
    .out_valid(mimo_valid),
    .x
