//==============================================================================
// mimo_detect.sv – 2x2 MIMO zero-forcing style detector (approx-aware)
//
// For each resource element:
//   Y = H X + N
//   X_hat ≈ H^{-1} Y   (simplified ZF / matched path for behavioural RTL)
//
// Under approx_en, multiplies use truncated arithmetic (intensity cut).
//==============================================================================

`timescale 1ns / 1ps

module mimo_detect #(
  parameter int WIDTH = 16
) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       approx_en,
  input  logic                       in_valid,

  // Received vector Y (2 RX antennas), complex
  input  logic [WIDTH-1:0]           y0_re, y0_im,
  input  logic [WIDTH-1:0]           y1_re, y1_im,

  // Channel matrix H (2x2), complex
  input  logic [WIDTH-1:0]           h00_re, h00_im,
  input  logic [WIDTH-1:0]           h01_re, h01_im,
  input  logic [WIDTH-1:0]           h10_re, h10_im,
  input  logic [WIDTH-1:0]           h11_re, h11_im,

  output logic                       out_valid,
  // Detected X (2 streams)
  output logic [WIDTH-1:0]           x0_re, x0_im,
  output logic [WIDTH-1:0]           x1_re, x1_im
);

  //--------------------------------------------------------------------------
  // Matched-filter / ZF-lite:
  //   x0 ≈ h00* y0 + h10* y1
  //   x1 ≈ h01* y0 + h11* y1
  // conj(H) applied approximately via real/imag cross terms
  //--------------------------------------------------------------------------
  logic [WIDTH-1:0] a00, a01, a10, a11;
  logic [WIDTH-1:0] b00, b01, b10, b11;
  logic [WIDTH-1:0] s0r, s0i, s1r, s1i;

  // Real parts of conj(H) * Y contributions
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_a00 (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h00_re), .op_b(y0_re), .result(a00), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_a01 (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h00_im), .op_b(y0_im), .result(a01), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_a10 (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h10_re), .op_b(y1_re), .result(a10), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_a11 (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h10_im), .op_b(y1_im), .result(a11), .result_valid()
  );

  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_b00 (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h01_re), .op_b(y0_re), .result(b00), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_b01 (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h01_im), .op_b(y0_im), .result(b01), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_b10 (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h11_re), .op_b(y1_re), .result(b10), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_b11 (
    .clk(clk), .rst_n(rst_n), .opcode(3'd2), .approx_en(approx_en),
    .op_a(h11_im), .op_b(y1_im), .result(b11), .result_valid()
  );

  // x0_re ≈ (h00_re y0_re + h00_im y0_im) + (h10_re y1_re + h10_im y1_im)
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_s0r_a (
    .clk(clk), .rst_n(rst_n), .opcode(3'd0), .approx_en(approx_en),
    .op_a(a00), .op_b(a01), .result(s0r), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_s0r_b (
    .clk(clk), .rst_n(rst_n), .opcode(3'd0), .approx_en(approx_en),
    .op_a(s0r), .op_b(a10), .result(x0_re), .result_valid()
  );

  // x1_re similarly
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_s1r_a (
    .clk(clk), .rst_n(rst_n), .opcode(3'd0), .approx_en(approx_en),
    .op_a(b00), .op_b(b01), .result(s1r), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_s1r_b (
    .clk(clk), .rst_n(rst_n), .opcode(3'd0), .approx_en(approx_en),
    .op_a(s1r), .op_b(b10), .result(x1_re), .result_valid()
  );

  // Imag paths (simplified behavioural)
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_s0i (
    .clk(clk), .rst_n(rst_n), .opcode(3'd1), .approx_en(approx_en),
    .op_a(y0_im), .op_b(a11), .result(x0_im), .result_valid()
  );
  approx_alu #(.WIDTH(WIDTH), .TRUNC_BITS(2)) u_s1i (
    .clk(clk), .rst_n(rst_n), .opcode(3'd1), .approx_en(approx_en),
    .op_a(y1_im), .op_b(b11), .result(x1_im), .result_valid()
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) out_valid <= 1'b0;
    else        out_valid <= in_valid;
  end

endmodule : mimo_detect
