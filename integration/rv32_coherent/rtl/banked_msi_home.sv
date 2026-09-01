`timescale 1ns/1ps

// Two independently progressing directory banks. Requests to the same line
// always select the same bank; requests to different line-bank bits may make
// progress concurrently while retaining the existing per-bank MSI checks.
module banked_msi_home #(
  parameter int LINES_PER_BANK = 8,
  parameter int WORDS_PER_LINE = 4,
  parameter int MEM_WORDS = 16384
) (
  input logic clk,
  input logic rst_n,
  input logic [1:0] req_valid,
  output logic [1:0] req_ready,
  input logic [1:0] req_write,
  input logic [1:0][31:0] req_addr,
  input logic [1:0][31:0] req_wdata,
  output logic [1:0] rsp_valid,
  input logic [1:0] rsp_ready,
  output logic [1:0][31:0] rsp_rdata,
  input logic mem_init_valid,
  input logic [31:0] mem_init_addr,
  input logic [31:0] mem_init_data,
  output logic [31:0] stat_invalidations,
  output logic [31:0] stat_interventions,
  output logic [31:0] stat_dirty_writebacks
);
  logic [1:0] request_bank;
  logic [1:0] response_bank;
  logic [1:0][1:0] bank_req_ready, bank_rsp_valid;
  logic [1:0][1:0][31:0] bank_rsp_data;
  logic [1:0][31:0] bank_invalidations, bank_interventions, bank_writebacks;
  logic [1:0][31:0] unused_read_miss, unused_write_miss;

  for (genvar h = 0; h < 2; h++) begin : g_route
    assign request_bank[h] = req_addr[h][4];
    assign req_ready[h] = bank_req_ready[request_bank[h]][h];
    assign rsp_valid[h] = bank_rsp_valid[0][h] || bank_rsp_valid[1][h];
    assign rsp_rdata[h] = bank_rsp_valid[response_bank[h]][h] ?
                          bank_rsp_data[response_bank[h]][h] : '0;
    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) response_bank[h] <= 1'b0;
      else if (req_valid[h] && req_ready[h]) response_bank[h] <= request_bank[h];
    end
  end

  assign stat_invalidations = bank_invalidations[0] + bank_invalidations[1];
  assign stat_interventions = bank_interventions[0] + bank_interventions[1];
  assign stat_dirty_writebacks = bank_writebacks[0] + bank_writebacks[1];

  for (genvar bank = 0; bank < 2; bank++) begin : g_bank
    logic c0_req_valid, c1_req_valid;
    logic c0_rsp_ready, c1_rsp_ready;
    assign c0_req_valid = req_valid[0] && request_bank[0] == bank;
    assign c1_req_valid = req_valid[1] && request_bank[1] == bank;
    assign c0_rsp_ready = rsp_ready[0] && response_bank[0] == bank;
    assign c1_rsp_ready = rsp_ready[1] && response_bank[1] == bank;
    msi_two_cache_subsystem #(
      .LINES(LINES_PER_BANK), .WORDS_PER_LINE(WORDS_PER_LINE), .MEM_WORDS(MEM_WORDS)
    ) home_bank (
      .clk, .rst_n,
      .c0_req_valid, .c0_req_ready(bank_req_ready[bank][0]),
      .c0_req_write(req_write[0]), .c0_req_addr(req_addr[0]), .c0_req_wdata(req_wdata[0]),
      .c0_rsp_valid(bank_rsp_valid[bank][0]), .c0_rsp_ready,
      .c0_rsp_rdata(bank_rsp_data[bank][0]),
      .c1_req_valid, .c1_req_ready(bank_req_ready[bank][1]),
      .c1_req_write(req_write[1]), .c1_req_addr(req_addr[1]), .c1_req_wdata(req_wdata[1]),
      .c1_rsp_valid(bank_rsp_valid[bank][1]), .c1_rsp_ready,
      .c1_rsp_rdata(bank_rsp_data[bank][1]),
      .mem_init_valid(mem_init_valid && mem_init_addr[4] == bank),
      .mem_init_addr, .mem_init_data,
      .stat_read_miss(unused_read_miss[bank]), .stat_write_miss(unused_write_miss[bank]),
      .stat_invalidations(bank_invalidations[bank]),
      .stat_interventions(bank_interventions[bank]),
      .stat_dirty_writebacks(bank_writebacks[bank])
    );
  end

`ifndef SYNTHESIS
  a_response_single_bank_h0: assert property (@(posedge clk) disable iff (!rst_n)
    !(bank_rsp_valid[0][0] && bank_rsp_valid[1][0]));
  a_response_single_bank_h1: assert property (@(posedge clk) disable iff (!rst_n)
    !(bank_rsp_valid[0][1] && bank_rsp_valid[1][1]));
`endif
endmodule
