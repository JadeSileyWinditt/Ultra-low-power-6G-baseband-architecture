//==============================================================================
// tb_rx_mimo.sv – RX chain with MIMO under FREE / BOUNDARY / BOUND
//==============================================================================

`timescale 1ns / 1ps

module tb_rx_mimo;

  logic clk, rst_n;
  initial begin clk = 0; forever #5 clk = ~clk; end

  localparam int W = 16;
  localparam int N_BF = 4;
  localparam int N_ST = 3;
  localparam int N_SC = 8;

  logic approx_en, skip_noncritical;
  logic [1:0] prune_level;
  logic in_valid, out_valid, csi_valid;
  logic [W-1:0] in_re [N_SC], in_im [N_SC];
  logic [W-1:0] in_re_a1 [N_SC], in_im_a1 [N_SC];
  logic [W-1:0] tw_re [N_ST][N_BF], tw_im [N_ST][N_BF];
  logic [W-1:0] h_re [N_SC], h_im [N_SC];
  logic [W-1:0] h00_re [N_SC], h00_im [N_SC];
  logic [W-1:0] h01_re [N_SC], h01_im [N_SC];
  logic [W-1:0] h10_re [N_SC], h10_im [N_SC];
  logic [W-1:0] h11_re [N_SC], h11_im [N_SC];
  logic [W-1:0] llr0 [N_SC], llr1 [N_SC];
  logic [7:0]   decoded_bits;
  logic         decode_valid;
  logic         crc_ok;

  rx_chain #(
    .WIDTH(W), .N_BUTTERFLIES(N_BF), .N_STAGES(N_ST), .N_SC(N_SC)
  ) u_dut (
    .clk(clk), .rst_n(rst_n),
    .approx_en(approx_en),
    .skip_noncritical(skip_noncritical),
    .prune_level(prune_level),
    .in_valid(in_valid),
    .in_re(in_re), .in_im(in_im),
    .tw_re(tw_re), .tw_im(tw_im),
    .h_re(h_re), .h_im(h_im),
    .in_re_a1(in_re_a1), .in_im_a1(in_im_a1),
    .h00_re(h00_re), .h00_im(h00_im),
    .h01_re(h01_re), .h01_im(h01_im),
    .h10_re(h10_re), .h10_im(h10_im),
    .h11_re(h11_re), .h11_im(h11_im),
    .out_valid(out_valid),
    .llr0(llr0), .llr1(llr1),
    .decoded_bits(decoded_bits), .decode_valid(decode_valid), .crc_ok(crc_ok)
  );

  integer i, s;
  initial begin
    rst_n = 0;
    approx_en = 0; skip_noncritical = 0; prune_level = 0; in_valid = 0;

    for (i = 0; i < N_SC; i++) begin
      in_re[i]    = 16'h0120 + i*5; in_im[i]    = 16'h0030 + i*2;
      in_re_a1[i] = 16'h00E0 + i*3; in_im_a1[i] = 16'h0028 + i;
      h_re[i] = 16'h00A0; h_im[i] = 16'h0020;
      // Per-SC 2×2 channel (mild frequency selectivity)
      h00_re[i] = 16'h00C0 + i; h00_im[i] = 16'h0010;
      h01_re[i] = 16'h0040;     h01_im[i] = 16'h0020;
      h10_re[i] = 16'h0030;     h10_im[i] = 16'h0018;
      h11_re[i] = 16'h00B0 - i; h11_im[i] = 16'h0008;
    end
    for (s = 0; s < N_ST; s++)
      for (i = 0; i < N_BF; i++) begin
        tw_re[s][i] = 16'h00C0; tw_im[s][i] = 16'h0018;
      end

    repeat (12) @(posedge clk);
    rst_n = 1;
    repeat (4) @(posedge clk);

    $display("=== RX + MIMO Chain ===");
    $display("mode       approx  skip  prune  valid  llr0[0]");

    // FREE
    approx_en = 0; skip_noncritical = 0; prune_level = 0;
    in_valid = 1; @(posedge clk); in_valid = 0;
    repeat (N_ST + 10) @(posedge clk);
    $display("FREE       %0d      %0d     %0d      %0d     0x%04h",
             approx_en, skip_noncritical, prune_level, out_valid, llr0[0]);

    // BOUNDARY
    approx_en = 1; skip_noncritical = 0; prune_level = 1;
    in_valid = 1; @(posedge clk); in_valid = 0;
    repeat (N_ST + 10) @(posedge clk);
    $display("BOUNDARY   %0d      %0d     %0d      %0d     0x%04h",
             approx_en, skip_noncritical, prune_level, out_valid, llr0[0]);

    // BOUND
    approx_en = 1; skip_noncritical = 1; prune_level = 2;
    in_valid = 1; @(posedge clk); in_valid = 0;
    repeat (N_ST + 10) @(posedge clk);
    $display("BOUND      %0d      %0d     %0d      %0d     0x%04h",
             approx_en, skip_noncritical, prune_level, out_valid, llr0[0]);

    $display("=== RX+MIMO test finished ===");
    $finish;
  end

endmodule : tb_rx_mimo
