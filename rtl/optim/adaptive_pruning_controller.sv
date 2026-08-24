// adaptive_pruning_controller.sv – Adaptive intensity reduction (v2)
// Software twin: python/optim/adaptive_pruning.py
//==============================================================================

`timescale 1ns / 1ps

module adaptive_pruning_controller #(
  parameter int WINDOW = 8
) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic [15:0]                throttle_q16,
  input  logic [1:0]                 region_code,        // 0=BOUND, 1=BOUNDARY, 2=FREE
  input  logic [15:0]                boundary_measure_q16,
  input  logic [15:0]                entropy_q16,
  output logic                       approx_en,
  output logic [1:0]                 prune_level,        // 0=none, 1=light, 2=aggressive
  output logic                       skip_noncritical
);

  localparam logic [15:0] THR_LIGHT = 16'h4000; // ~0.25
  localparam logic [15:0] THR_AGGR  = 16'h8C00; // ~0.55
  localparam logic [15:0] HYST      = 16'h1400; // ~0.08

  logic [15:0] hist [WINDOW];
  logic [$clog2(WINDOW):0] hist_cnt;
  logic [15:0] last_pressure;
  logic [1:0]  last_prune;
  logic        last_approx, last_skip;

  logic [15:0] inst_pressure;
  always_comb begin
    logic [16:0] acc;
    acc = {1'b0, boundary_measure_q16} >> 1;                 // 0.5 * B
    acc = acc + ((17'h10000 - {1'b0, throttle_q16}) >> 2);   // 0.25 * (1-thr)
    if (region_code == 2'd0)
      acc = acc + 17'h3000;                                  // BOUND boost
    else if (region_code == 2'd1)
      acc = acc + 17'h1800;                                  // BOUNDARY boost
    if (acc > 17'hFFFF)
      inst_pressure = 16'hFFFF;
    else
      inst_pressure = acc[15:0];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      hist_cnt      <= '0;
      last_pressure <= '0;
      last_prune    <= 2'd0;
      last_approx   <= 1'b0;
      last_skip     <= 1'b0;
      approx_en     <= 1'b0;
      prune_level   <= 2'd0;
      skip_noncritical <= 1'b0;
      for (int i = 0; i < WINDOW; i++)
        hist[i] <= '0;
    end else begin
      for (int i = WINDOW-1; i > 0; i--)
        hist[i] <= hist[i-1];
      hist[0] <= inst_pressure;
      if (hist_cnt < WINDOW)
        hist_cnt <= hist_cnt + 1;

      logic [15:0] delta;
      if (inst_pressure > last_pressure)
        delta = inst_pressure - last_pressure;
      else
        delta = last_pressure - inst_pressure;

      if (delta < HYST && hist_cnt > 2) begin
        approx_en        <= last_approx;
        prune_level      <= last_prune;
        skip_noncritical <= last_skip;
      end else begin
        if (inst_pressure < THR_LIGHT) begin
          approx_en        <= 1'b0;
          prune_level      <= 2'd0;
          skip_noncritical <= 1'b0;
        end else if (inst_pressure < THR_AGGR) begin
          approx_en        <= 1'b1;
          prune_level      <= 2'd1;
          skip_noncritical <= 1'b0;
        end else begin
          approx_en        <= 1'b1;
          prune_level      <= 2'd2;
          skip_noncritical <= 1'b1;
        end
        last_pressure <= inst_pressure;
        last_approx   <= approx_en;
        last_prune    <= prune_level;
        last_skip     <= skip_noncritical;
      end
    end
  end

endmodule : adaptive_pruning_controller
