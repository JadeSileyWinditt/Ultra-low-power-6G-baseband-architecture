`timescale 1ns / 1ps

module ldpc_decoder_stub #(
  parameter int WIDTH = 16,
  parameter int N = 64,
  parameter int K = 32,
  parameter int MAX_ITER = 8
) (
  input  logic clk, rst_n, approx_en, skip_noncritical, in_valid,
  input  logic [WIDTH-1:0] llr [N],
  output logic out_valid,
  output logic [K-1:0] info_bits,
  output logic crc_ok
);

  logic [3:0] iter_cnt, iter_limit;
  logic busy;

  always_comb begin
    if (skip_noncritical) iter_limit = 0;
    else if (approx_en)    iter_limit = 2;
    else                   iter_limit = MAX_ITER[3:0];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid <= 0; info_bits <= 0; crc_ok <= 0;
      iter_cnt <= 0; busy <= 0;
    end else begin
      out_valid <= 0;
      if (in_valid && !busy) begin
        busy <= 1; iter_cnt <= 0;
      end else if (busy) begin
        if (iter_cnt >= iter_limit) begin
          for (int i = 0; i < K; i++)
            info_bits[i] <= llr[i][WIDTH-1];
          crc_ok <= ~skip_noncritical;
          out_valid <= 1;
          busy <= 0;
        end else
          iter_cnt <= iter_cnt + 1;
      end
    end
  end
endmodule
