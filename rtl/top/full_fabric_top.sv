//==============================================================================
// full_fabric_top.sv – Configurable full-fabric top-level
//
// Set NUM_TILES = 2048 for the target architecture.
// For simulation keep it small (8 / 32 / 64).  The hierarchy
// (slices → regions → tiles) stays identical.
//==============================================================================

`timescale 1ns / 1ps

import tbu_params_pkg::*;

module full_fabric_top #(
  parameter int NUM_TILES        = 64,     // raise toward 2048; hierarchy is identical  // ← set to 2048 for full elaboration
  parameter int TILES_PER_SLICE  = 8,
  parameter int N_REGIONS        = 4,
  parameter int ALU_WIDTH        = 16,
  parameter int N_BUTTERFLIES    = 4
) (
  input  logic                       clk,
  input  logic                       rst_n,

  input  logic [31:0]                ops_request,
  input  logic                       ops_valid,
  input  logic                       fft_in_valid,
  input  logic [ALU_WIDTH-1:0]       in_re  [N_BUTTERFLIES*2],
  input  logic [ALU_WIDTH-1:0]       in_im  [N_BUTTERFLIES*2],
  input  logic [ALU_WIDTH-1:0]       tw_re  [N_BUTTERFLIES],
  input  logic [ALU_WIDTH-1:0]       tw_im  [N_BUTTERFLIES],

  output logic [1:0]                 global_region_code,
  output logic                       global_envelope_alarm,
  output logic                       any_fft_valid
);

  localparam int N_SLICES = (NUM_TILES + TILES_PER_SLICE - 1) / TILES_PER_SLICE;

  multi_slice_top #(
    .N_SLICES        (N_SLICES),
    .TILES_PER_SLICE (TILES_PER_SLICE),
    .N_REGIONS       (N_REGIONS),
    .ALU_WIDTH       (ALU_WIDTH),
    .N_BUTTERFLIES   (N_BUTTERFLIES)
  ) u_fabric (
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

endmodule : full_fabric_top
