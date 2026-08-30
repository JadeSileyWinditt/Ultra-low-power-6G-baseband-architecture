//==============================================================================
// mimo_detect.sv – 2×2 MIMO Zero-Forcing / MMSE-lite detector (approx-aware)
//
//   Y = H X + N
//   ZF   : X̂ ≈ H⁺ Y
//   MMSE : X̂ ≈ (HᴴH + σ²I)⁻¹ Hᴴ Y     (σ² folded into det as det + noise_var)
//
// Behavioural reciprocal is a shift-scale stub. Silicon would use NR / LUT
// under the same approx_en gate.
//==============================================================================

`timescale 1ns / 1ps

module mimo_detect #(
  parameter int WIDTH = 16
) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       approx_en,
  input  logic                       mmse_en,
  input  logic                       in_valid,
  input  logic [WIDTH-1:0]           noise_var,

  input  logic [WIDTH-1:0]           y0_re, y0_im,
  input  logic [WIDTH-1:0]           y1_re, y1_im,

  input  logic [WIDTH-1:0]           h00_re, h00_im,
  input  logic [WIDTH-1:0]           h01_re, h01_im,
  input  logic [WIDTH-1:0]           h10_re, h10_im,
  input  logic [WIDTH-1:0]           h11_re, h11_im,

  output logic                       out_valid,
  output logic [WIDTH-1:0]           x0_re, x0_im,
  output logic [WIDTH-1:0]           x1_re, x1_im
);

  logic [WIDTH-1:0] p00_11, p01_10, det_re;
  logic [WIDTH-1:0] inv_det;
  logic [WIDTH-1:0] det_reg;

  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_p00 (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h00_re), .op_b(h11_re), .result(p00_11), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_p01 (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h01_re), .op_b(h10_re), .result(p01_10), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_det (
    .clk(clk), .rst_n(rst_n), .opcode(3'd1), .approx_en(approx_en),
    .op_a(p00_11), .op_b(p01_10), .result(det_re), .result_valid()
  );

  always_comb begin
    det_reg = mmse_en ? (det_re + noise_var) : det_re;
    if (det_reg == '0)
      inv_det = {1'b0, {(WIDTH-1){1'b1}}};
    else
      inv_det = (16'h4000 / (det_reg[7:0] ? det_reg[7:0] : 8'd1));
  end

  logic [WIDTH-1:0] t0a, t0b, t0s, t1a, t1b, t1s;
  logic [WIDTH-1:0] t0i_a, t0i_b, t1i_a, t1i_b;

  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_t0a (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h11_re), .op_b(y0_re), .result(t0a), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_t0b (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h01_re), .op_b(y1_re), .result(t0b), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_t0s (
    .clk(clk), .rst_n(rst_n), .opcode(3'd1), .approx_en(approx_en),
    .op_a(t0a), .op_b(t0b), .result(t0s), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_x0r (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(t0s), .op_b(inv_det), .result(x0_re), .result_valid()
  );

  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_t1a (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h10_re), .op_b(y0_re), .result(t1a), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_t1b (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h00_re), .op_b(y1_re), .result(t1b), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_t1s (
    .clk(clk), .rst_n(rst_n), .opcode(3'd1), .approx_en(approx_en),
    .op_a(t1b), .op_b(t1a), .result(t1s), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_x1r (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(t1s), .op_b(inv_det), .result(x1_re), .result_valid()
  );

  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_t0ia (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h11_im), .op_b(y0_im), .result(t0i_a), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_t0ib (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h01_im), .op_b(y1_im), .result(t0i_b), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_x0i (
    .clk(clk), .rst_n(rst_n), .opcode(3'd1), .approx_en(approx_en),
    .op_a(t0i_a), .op_b(t0i_b), .result(x0_im), .result_valid()
  );

  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_t1ia (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h00_im), .op_b(y1_im), .result(t1i_a), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_t1ib (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h10_im), .op_b(y0_im), .result(t1i_b), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_x1i (
    .clk(clk), .rst_n(rst_n), .opcode(3'd1), .approx_en(approx_en),
    .op_a(t1i_a), .op_b(t1i_b), .result(x1_im), .result_valid()
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) out_valid <= 1'b0;
    else        out_valid <= in_valid;
  end

endmodule : mimo_detect
