//==============================================================================
// rx_chain.sv – OFDM receive path with 2×2 MIMO + polar decode
//
//   time-domain (2 antennas) → dual FFT pipelines → per-SC MIMO ZF detect
//   → dual soft demap → polar decoder (N=16, K=8 + CRC-4)
//
// All stages respect TBU pruning / approx_en.
// Per-SC MIMO uses csi_bank for thermal-aware CSI hold + approx quantisation.
// Fresh CSI when csi_valid=1; under prune_level the same H is reused.
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
  input  logic                       mmse_en,
  input  logic [WIDTH-1:0]           noise_var,
  input  logic                       skip_noncritical,
  input  logic [1:0]                 prune_level,

  input  logic                       in_valid,
  // Antenna 0 time-domain
  input  logic [WIDTH-1:0]           in_re  [N_SC],
  input  logic [WIDTH-1:0]           in_im  [N_SC],
  // Antenna 1 time-domain
  input  logic [WIDTH-1:0]           in_re_a1 [N_SC],
  input  logic [WIDTH-1:0]           in_im_a1 [N_SC],

  input  logic [WIDTH-1:0]           tw_re  [N_STAGES][N_BUTTERFLIES],
  input  logic [WIDTH-1:0]           tw_im  [N_STAGES][N_BUTTERFLIES],

  // Per-subcarrier single-stream channel (legacy / fallback path)
  input  logic [WIDTH-1:0]           h_re   [N_SC],
  input  logic [WIDTH-1:0]           h_im   [N_SC],

  // Per-SC 2×2 channel matrix (fresh CSI)
  input  logic [WIDTH-1:0]           h00_re [N_SC], h00_im [N_SC],
  input  logic [WIDTH-1:0]           h01_re [N_SC], h01_im [N_SC],
  input  logic [WIDTH-1:0]           h10_re [N_SC], h10_im [N_SC],
  input  logic [WIDTH-1:0]           h11_re [N_SC], h11_im [N_SC],
  input  logic                       csi_valid,

  output logic                       out_valid,
  output logic [WIDTH-1:0]           llr0   [N_SC],
  output logic [WIDTH-1:0]           llr1   [N_SC],
  output logic [7:0]                 decoded_bits,
  output logic                       decode_valid,
  output logic                       crc_ok
);

  logic                 sym0_valid, sym1_valid;
  logic [WIDTH-1:0]     y0_re [N_SC], y0_im [N_SC];
  logic [WIDTH-1:0]     y1_re [N_SC], y1_im [N_SC];

  symbol_chain #(
    .WIDTH(WIDTH), .N_BUTTERFLIES(N_BUTTERFLIES),
    .N_STAGES(N_STAGES), .N_SC(N_SC)
  ) u_symbol0 (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en),
    .skip_noncritical(skip_noncritical),
    .prune_level(prune_level),
    .in_valid(in_valid),
    .in_re(in_re), .in_im(in_im),
    .tw_re(tw_re), .tw_im(tw_im),
    .h_re(h_re), .h_im(h_im),
    .out_valid(sym0_valid),
    .x_re(y0_re), .x_im(y0_im)
  );

  symbol_chain #(
    .WIDTH(WIDTH), .N_BUTTERFLIES(N_BUTTERFLIES),
    .N_STAGES(N_STAGES), .N_SC(N_SC)
  ) u_symbol1 (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en),
    .skip_noncritical(skip_noncritical),
    .prune_level(prune_level),
    .in_valid(in_valid),
    .in_re(in_re_a1), .in_im(in_im_a1),
    .tw_re(tw_re), .tw_im(tw_im),
    .h_re(h_re), .h_im(h_im),
    .out_valid(sym1_valid),
    .x_re(y1_re), .x_im(y1_im)
  );

  logic                 csi_out_valid;
  logic [WIDTH-1:0]     h00_re_h [N_SC], h00_im_h [N_SC];
  logic [WIDTH-1:0]     h01_re_h [N_SC], h01_im_h [N_SC];
  logic [WIDTH-1:0]     h10_re_h [N_SC], h10_im_h [N_SC];
  logic [WIDTH-1:0]     h11_re_h [N_SC], h11_im_h [N_SC];
  logic [N_SC-1:0]      csi_held;

  csi_bank #(
    .WIDTH(WIDTH), .N_SC(N_SC), .HOLD_MAX(8)
  ) u_csi_bank (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en),
    .prune_level(prune_level),
    .in_valid(sym0_valid & sym1_valid),
    .h00_re_i(h00_re), .h00_im_i(h00_im),
    .h01_re_i(h01_re), .h01_im_i(h01_im),
    .h10_re_i(h10_re), .h10_im_i(h10_im),
    .h11_re_i(h11_re), .h11_im_i(h11_im),
    .csi_valid(csi_valid),
    .out_valid(csi_out_valid),
    .h00_re(h00_re_h), .h00_im(h00_im_h),
    .h01_re(h01_re_h), .h01_im(h01_im_h),
    .h10_re(h10_re_h), .h10_im(h10_im_h),
    .h11_re(h11_re_h), .h11_im(h11_im_h),
    .held(csi_held)
  );

  logic                 mimo_fire;
  assign mimo_fire = csi_out_valid & ~skip_noncritical;

  logic                 mimo_valid [N_SC];
  logic [WIDTH-1:0]     x0_re [N_SC], x0_im [N_SC];
  logic [WIDTH-1:0]     x1_re [N_SC], x1_im [N_SC];

  genvar gi;
  generate
    for (gi = 0; gi < N_SC; gi++) begin : g_mimo
      mimo_detect #(.WIDTH(WIDTH)) u_mimo (
        .clk(clk), .rst_n(rst_n),
        .approx_en(approx_en),
        .mmse_en(mmse_en),
        .noise_var(noise_var),
        .in_valid(mimo_fire),
        .y0_re(y0_re[gi]), .y0_im(y0_im[gi]),
        .y1_re(y1_re[gi]), .y1_im(y1_im[gi]),
        .h00_re(h00_re_h[gi]), .h00_im(h00_im_h[gi]),
        .h01_re(h01_re_h[gi]), .h01_im(h01_im_h[gi]),
        .h10_re(h10_re_h[gi]), .h10_im(h10_im_h[gi]),
        .h11_re(h11_re_h[gi]), .h11_im(h11_im_h[gi]),
        .out_valid(mimo_valid[gi]),
        .x0_re(x0_re[gi]), .x0_im(x0_im[gi]),
        .x1_re(x1_re[gi]), .x1_im(x1_im[gi])
      );
    end
  endgenerate

  logic any_mimo_valid;
  assign any_mimo_valid = mimo_valid[0];

  logic demap0_valid, demap1_valid;
  logic [WIDTH-1:0] llr0_s0 [N_SC], llr1_s0 [N_SC];
  logic [WIDTH-1:0] llr0_s1 [N_SC], llr1_s1 [N_SC];

  soft_demap #(.WIDTH(WIDTH), .N_SC(N_SC)) u_demap0 (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en),
    .in_valid(any_mimo_valid),
    .x_re(x0_re), .x_im(x0_im),
    .out_valid(demap0_valid),
    .llr0(llr0_s0), .llr1(llr1_s0)
  );

  soft_demap #(.WIDTH(WIDTH), .N_SC(N_SC)) u_demap1 (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en),
    .in_valid(any_mimo_valid),
    .x_re(x1_re), .x_im(x1_im),
    .out_valid(demap1_valid),
    .llr0(llr0_s1), .llr1(llr1_s1)
  );

  logic [WIDTH-1:0] dec_llr [16];
  always_comb begin
    for (int i = 0; i < N_SC; i++) begin
      dec_llr[2*i]   = llr0_s0[i];
      dec_llr[2*i+1] = llr0_s1[i];
    end
  end

  polar_decoder #(
    .WIDTH(WIDTH), .N(16), .K(8)
  ) u_dec (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en),
    .skip_noncritical(skip_noncritical),
    .in_valid(demap0_valid & ~skip_noncritical),
    .llr(dec_llr),
    .out_valid(decode_valid),
    .info_bits(decoded_bits),
    .info_llr(),
    .crc_ok(crc_ok)
  );

  always_comb begin
    if (skip_noncritical) begin
      out_valid = sym0_valid;
      for (int i = 0; i < N_SC; i++) begin
        llr0[i] = y0_re[i];
        llr1[i] = y0_im[i];
      end
    end else begin
      out_valid = demap0_valid & demap1_valid;
      for (int i = 0; i < N_SC; i++) begin
        llr0[i] = llr0_s0[i];
        llr1[i] = llr0_s1[i];
      end
    end
  end

endmodule : rx_chain
