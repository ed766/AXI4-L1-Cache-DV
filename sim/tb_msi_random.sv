`timescale 1ns/1ps

module tb_msi_random;
  logic clk = 0, rst_n = 0;
  always #5 clk <= ~clk;
  logic c0_req_valid, c0_req_ready, c0_req_write;
  logic [31:0] c0_req_addr, c0_req_wdata;
  logic c0_rsp_valid, c0_rsp_ready;
  logic [31:0] c0_rsp_rdata;
  logic c1_req_valid, c1_req_ready, c1_req_write;
  logic [31:0] c1_req_addr, c1_req_wdata;
  logic c1_rsp_valid, c1_rsp_ready;
  logic [31:0] c1_rsp_rdata;
  logic mem_init_valid;
  logic [31:0] mem_init_addr, mem_init_data;
  logic [31:0] stat_read_miss, stat_write_miss, stat_invalidations;
  logic [31:0] stat_interventions, stat_dirty_writebacks;
  integer seed = 1;
  integer operations = 120;
  integer trace_fd;
  string trace_file;
  logic [31:0] random_state;

  msi_two_cache_subsystem dut (.*);

  function automatic logic [31:0] next_random(input logic [31:0] value);
    next_random = value ^ (value << 13);
    next_random = next_random ^ (next_random >> 17);
    next_random = next_random ^ (next_random << 5);
  endfunction

  task automatic initialize_word(input int word);
    @(negedge clk); mem_init_valid = 1; mem_init_addr = word << 2;
    mem_init_data = 32'h1000_0000 ^ word;
    @(posedge clk); @(negedge clk); mem_init_valid = 0;
  endtask

  task automatic issue(input bit owner, input bit write, input logic [31:0] addr,
                       input logic [31:0] wdata, input int op_index);
    logic [31:0] observed;
    @(negedge clk);
    if (!owner) begin
      c0_req_valid = 1; c0_req_write = write; c0_req_addr = addr; c0_req_wdata = wdata;
      do @(posedge clk); while (!c0_req_ready);
      @(negedge clk); c0_req_valid = 0;
      do @(posedge clk); while (!c0_rsp_valid);
      observed = c0_rsp_rdata;
    end else begin
      c1_req_valid = 1; c1_req_write = write; c1_req_addr = addr; c1_req_wdata = wdata;
      do @(posedge clk); while (!c1_req_ready);
      @(negedge clk); c1_req_valid = 0;
      do @(posedge clk); while (!c1_rsp_valid);
      observed = c1_rsp_rdata;
    end
    $fdisplay(trace_fd, "OP,%0d,%0d,%0d,%08x,%08x,%08x", op_index, owner, write, addr, wdata, observed);
    @(posedge clk);
  endtask

  initial begin
    void'($value$plusargs("SEED=%d", seed));
    void'($value$plusargs("OPS=%d", operations));
    if (!$value$plusargs("TRACE_FILE=%s", trace_file)) $fatal(1, "TRACE_FILE required");
    trace_fd = $fopen(trace_file, "w");
    if (!trace_fd) $fatal(1, "cannot open trace");
    c0_req_valid = 0; c0_req_write = 0; c0_req_addr = 0; c0_req_wdata = 0;
    c1_req_valid = 0; c1_req_write = 0; c1_req_addr = 0; c1_req_wdata = 0;
    c0_rsp_ready = 1; c1_rsp_ready = 1; mem_init_valid = 0;
    repeat (4) @(posedge clk); rst_n = 1;
    for (int word = 0; word < 256; word++) initialize_word(word);
    random_state = seed;
    for (int op = 0; op < operations; op++) begin
      bit owner, write;
      logic [31:0] address, data;
      random_state = next_random(random_state);
      owner = random_state[0];
      write = random_state[3:1] == 3'b000 || random_state[3:1] == 3'b001;
      // Half of accesses stay in four hot lines to force sharing and ping-pong.
      if (random_state[4])
        address = {24'd0, random_state[6:5], random_state[8:7], 2'b00};
      else
        address = {22'd0, random_state[12:5], 2'b00};
      data = 32'hc000_0000 ^ (seed << 12) ^ op ^ random_state;
      issue(owner, write, address, data, op);
    end
    $fdisplay(trace_fd, "STATS,%0d,%0d,%0d,%0d,%0d", stat_read_miss, stat_write_miss,
              stat_invalidations, stat_interventions, stat_dirty_writebacks);
    $fclose(trace_fd);
    $display("MSI_RANDOM|status=PASS|seed=%0d|operations=%0d", seed, operations);
    $finish;
  end

  initial begin repeat (50000) @(posedge clk); $fatal(1, "MSI random timeout"); end
endmodule
