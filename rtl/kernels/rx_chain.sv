//==============================================================================
// tx_chain.sv – Transmit path: polar encode → constellation map → IFFT
//
// Channel coding (polar N=16, K=8 + CRC-4) sits in front of the mapper so
// that the whole TX pipeline remains under TBU approx / prune control.
// 16 coded bits map onto 8 QPSK symbols (2 bits per SC).
//==============================================================================

`timescale 1ns / 1ps

module tx_chain #(
  parameter int WIDTH         = 16,
  parameter int N_BUTTERFLIES = 4,
  parameter int N_STAGES      = 3,
  parameter int N_SC          = 8,
  parameter int K_INFO        = 8,
  parameter int N_POLAR       = 16
) (
  input  logic                       clk,
  input  logic                       rst_n,

  input  logic                       approx_en,
  input  logic                       skip_noncritical,
  input  logic [1:0]                 prune_level,

  input  logic                       in_valid,
  // Information bits (packed).  Lower 4 bits used as payload; CRC is
  // computed inside the encoder.
  input  logic [1:0]                 bits   [N_SC],
  input  logic [WIDTH-1:0]           tw_re  [N_STAGES][N_BUTTERFLIES],
  input  logic [WIDTH-1:0]           tw_im  [N_STAGES][N_BUTTERFLIES],

  output logic                       out_valid,
  output logic [WIDTH-1:0]           out_re [N_SC],
  output logic [WIDTH-1:0]           out_im [N_SC]
);

  //--------------------------------------------------------------------------
  // Pack payload bits (encoder adds CRC-4 itself)
  //--------------------------------------------------------------------------
  logic [K_INFO-1:0] info;
  always_comb begin
    info = '0;
    info[0] = bits[0][0];
    info[1] = bits[1][0];
    info[2] = bits[2][0];
    info[3] = bits[3][0];
    // upper nibble left 0 – encoder fills CRC
  end

  //--------------------------------------------------------------------------
  // Polar encoder (N=16, K=8)
  //--------------------------------------------------------------------------
  logic                 enc_valid;
  logic [N_POLAR-1:0]   coded;

  polar_encoder #(
    .N(N_POLAR), .K(K_INFO)
  ) u_enc (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en),
    .skip_noncritical(skip_noncritical),
    .in_valid(in_valid),
    .info_bits(info),
    .out_valid(enc_valid),
    .coded_bits(coded)
  );

  // Map 16 coded bits onto 8 QPSK symbols (2 bits per SC)
  logic [1:0] map_bits [N_SC];
  always_comb begin
    for (int i = 0; i < N_SC; i++)
      map_bits[i] = {coded[2*i+1], coded[2*i]};
  end

  //--------------------------------------------------------------------------
  // Constellation map
  //--------------------------------------------------------------------------
  logic                 map_valid;
  logic [WIDTH-1:0]     s_re [N_SC];
  logic [WIDTH-1:0]     s_im [N_SC];

  constellation_map #(
    .WIDTH(WIDTH), .N_SC(N_SC)
  ) u_map (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en),
    .in_valid(enc_valid),
    .bits(map_bits),
    .out_valid(map_valid),
    .s_re(s_re), .s_im(s_im)
  );

  //--------------------------------------------------------------------------
  // IFFT (reuse OFDM pipeline)
  //--------------------------------------------------------------------------
  logic fft_in_valid;
  assign fft_in_valid = map_valid & ~skip_noncritical;

  logic                 fft_valid;
  logic [WIDTH-1:0]     fft_re [N_SC];
  logic [WIDTH-1:0]     fft_im [N_SC];

  ofdm_fft_pipeline #(
    .WIDTH(WIDTH), .N_BUTTERFLIES(N_BUTTERFLIES), .N_STAGES(N_STAGES)
  ) u_ifft (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en),
    .skip_noncritical(1'b0),
    .prune_level(prune_level),
    .in_valid(fft_in_valid),
    .in_re(s_re), .in_im(s_im),
    .tw_re(tw_re), .tw_im(tw_im),
    .out_valid(fft_valid),
    .out_re(fft_re), .out_im(fft_im)
  );

  always_comb begin
    if (skip_noncritical) begin
      out_valid = map_valid;
      out_re    = s_re;
      out_im    = s_im;
    end else begin
      out_valid = fft_valid;
      out_re    = fft_re;
      out_im    = fft_im;
    end
  end

endmodule : tx_chain
