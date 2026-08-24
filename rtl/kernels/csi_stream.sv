mkdir -p rtl/kernels rtl/optim python/optim docs sim

# ---- 1) csi_stream.sv ----
cat > rtl/kernels/csi_stream.sv << 'EOF'
`timescale 1ns / 1ps
module csi_stream #(
  parameter int WIDTH = 16, parameter int HOLD_MAX = 8
) (
  input  logic clk, rst_n, approx_en, in_valid, csi_valid,
  input  logic [1:0] prune_level,
  input  logic [WIDTH-1:0] h00_re_i, h00_im_i, h01_re_i, h01_im_i,
  input  logic [WIDTH-1:0] h10_re_i, h10_im_i, h11_re_i, h11_im_i,
  output logic out_valid, held,
  output logic [WIDTH-1:0] h00_re, h00_im, h01_re, h01_im,
  output logic [WIDTH-1:0] h10_re, h10_im, h11_re, h11_im
);
  logic [WIDTH-1:0] h00_re_r, h00_im_r, h01_re_r, h01_im_r;
  logic [WIDTH-1:0] h10_re_r, h10_im_r, h11_re_r, h11_im_r;
  logic [3:0] hold_cnt, hold_limit;
  logic has_csi;
  always_comb case (prune_level)
    2'd0: hold_limit = 4'd1; 2'd1: hold_limit = 4'd4; default: hold_limit = HOLD_MAX[3:0];
  endcase
  function automatic logic [WIDTH-1:0] trunc(input logic [WIDTH-1:0] v, input logic a);
    trunc = a ? {v[WIDTH-1:4], 4'b0} : v;
  endfunction
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      {h00_re_r,h00_im_r,h01_re_r,h01_im_r,h10_re_r,h10_im_r,h11_re_r,h11_im_r} <= '0;
      hold_cnt <= '0; has_csi <= 0; out_valid <= 0; held <= 0;
    end else begin
      out_valid <= in_valid;
      if (csi_valid) begin
        h00_re_r <= trunc(h00_re_i, approx_en); h00_im_r <= trunc(h00_im_i, approx_en);
        h01_re_r <= trunc(h01_re_i, approx_en); h01_im_r <= trunc(h01_im_i, approx_en);
        h10_re_r <= trunc(h10_re_i, approx_en); h10_im_r <= trunc(h10_im_i, approx_en);
        h11_re_r <= trunc(h11_re_i, approx_en); h11_im_r <= trunc(h11_im_i, approx_en);
        hold_cnt <= 0; has_csi <= 1; held <= 0;
      end else if (in_valid && has_csi) begin
        if (hold_cnt < hold_limit) hold_cnt <= hold_cnt + 1;
        held <= 1;
      end else held <= 0;
    end
  end
  assign h00_re=h00_re_r; assign h00_im=h00_im_r;
  assign h01_re=h01_re_r; assign h01_im=h01_im_r;
  assign h10_re=h10_re_r; assign h10_im=h10_im_r;
  assign h11_re=h11_re_r; assign h11_im=h11_im_r;
endmodule

module csi_bank #(
  parameter int WIDTH=16, parameter int N_SC=8, parameter int HOLD_MAX=8
) (
  input  logic clk, rst_n, approx_en, in_valid, csi_valid,
  input  logic [1:0] prune_level,
  input  logic [WIDTH-1:0] h00_re_i[N_SC], h00_im_i[N_SC], h01_re_i[N_SC], h01_im_i[N_SC],
  input  logic [WIDTH-1:0] h10_re_i[N_SC], h10_im_i[N_SC], h11_re_i[N_SC], h11_im_i[N_SC],
  output logic out_valid,
  output logic [WIDTH-1:0] h00_re[N_SC], h00_im[N_SC], h01_re[N_SC], h01_im[N_SC],
  output logic [WIDTH-1:0] h10_re[N_SC], h10_im[N_SC], h11_re[N_SC], h11_im[N_SC],
  output logic [N_SC-1:0] held
);
  logic cell_valid [N_SC];
  genvar gi;
  generate for (gi = 0; gi < N_SC; gi++) begin : g_csi
    csi_stream #(.WIDTH(WIDTH), .HOLD_MAX(HOLD_MAX)) u_csi (
      .clk(clk), .rst_n(rst_n), .approx_en(approx_en), .prune_level(prune_level),
      .in_valid(in_valid), .csi_valid(csi_valid),
      .h00_re_i(h00_re_i[gi]), .h00_im_i(h00_im_i[gi]),
      .h01_re_i(h01_re_i[gi]), .h01_im_i(h01_im_i[gi]),
      .h10_re_i(h10_re_i[gi]), .h10_im_i(h10_im_i[gi]),
      .h11_re_i(h11_re_i[gi]), .h11_im_i(h11_im_i[gi]),
      .out_valid(cell_valid[gi]), .held(held[gi]),
      .h00_re(h00_re[gi]), .h00_im(h00_im[gi]),
      .h01_re(h01_re[gi]), .h01_im(h01_im[gi]),
      .h10_re(h10_re[gi]), .h10_im(h10_im[gi]),
      .h11_re(h11_re[gi]), .h11_im(h11_im[gi])
    );
  end endgenerate
  assign out_valid = cell_valid[0];
endmodule
EOF

echo "Created rtl/kernels/csi_stream.sv"
