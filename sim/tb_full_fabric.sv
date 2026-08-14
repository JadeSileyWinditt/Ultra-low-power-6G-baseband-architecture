//==============================================================================
// tb_full_fabric.sv – Smoke test for the configurable full-fabric top
//
// Default NUM_TILES is modest for simulation speed.  Change the parameter
// to explore larger configurations.
//==============================================================================

`timescale 1ns / 1ps

import tbu_params_pkg::*;

module tb_full_fabric;

  logic clk, rst_n;
  initial begin clk = 0; forever #5 clk = ~clk; end

  localparam int W = 16;
  localparam int N_BF = 4;

  logic [31:0] ops_request;
  logic        ops_valid, fft_in_valid;
  logic [W-1:0] in_re [N_BF*2], in_im [N_BF*2];
  logic [W-1:0] tw_re [N_BF], tw_im [N_BF];
  logic [1:0]  global_region_code;
  logic        global_envelope_alarm, any_fft_valid;

  full_fabric_top #(
    .NUM_TILES       (64),     // hierarchy scales to 2048; 64 for sim speed   // raise toward 2048 when ready
    .TILES_PER_SLICE (8),
    .N_REGIONS       (4),
    .ALU_WIDTH       (W),
    .N_BUTTERFLIES   (N_BF)
  ) u_dut (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .ops_request           (ops_request),
    .ops_valid             (ops_valid),
    .fft_in_valid          (fft_in_valid),
    .in_re                 (in_re),
    .in_im                 (in_im),
    .tw_re                 (tw_re),
    .tw_im                 (tw_im),
    .global_region_code    (global_region_code),
    .global_envelope_alarm (global_envelope_alarm),
    .any_fft_valid         (any_fft_valid)
  );

  string region_name;
  always_comb case (global_region_code)
    2'd0: region_name = "BOUND";
    2'd1: region_name = "BOUNDARY";
    2'd2: region_name = "FREE";
    default: region_name = "???";
  endcase

  integer i;
  initial begin
    rst_n = 0;
    ops_request = 0; ops_valid = 0; fft_in_valid = 0;
    for (i = 0; i < N_BF*2; i++) begin
      in_re[i] = 16'h0080 + i; in_im[i] = 16'h0010 + i;
    end
    for (i = 0; i < N_BF; i++) begin
      tw_re[i] = 16'h00A0; tw_im[i] = 16'h0020;
    end

    repeat (15) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    $display("=== Full Fabric Smoke Test ===");
    $display("time     ops      region     alarm  fft");

    for (i = 0; i < 10; i++) begin
      ops_request  = 32'd8_000_000 + i * 32'd12_000_000;
      ops_valid    = 1;
      fft_in_valid = 1;
      @(posedge clk);
      ops_valid = 0; fft_in_valid = 0;
      repeat (3) @(posedge clk);
      $display("%0t  %8d  %-8s   %0d     %0d",
               $time, ops_request, region_name,
               global_envelope_alarm, any_fft_valid);
    end

    $display("=== Smoke test finished ===");
    $finish;
  end

endmodule : tb_full_fabric
