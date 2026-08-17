`timescale 1ns/1ps

module tb_msi_two_cache;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

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
  integer failures = 0;
  integer checks = 0;

  msi_two_cache_subsystem dut (.*);

  task automatic initialize_word(input logic [31:0] addr, input logic [31:0] data);
    @(negedge clk);
    mem_init_valid = 1'b1;
    mem_init_addr = addr;
    mem_init_data = data;
    @(posedge clk);
    @(negedge clk);
    mem_init_valid = 1'b0;
  endtask

  task automatic access(
    input bit owner,
    input bit write,
    input logic [31:0] addr,
    input logic [31:0] wdata,
    input logic [31:0] expected,
    input string name
  );
    logic observed_valid;
    logic [31:0] observed;
    @(negedge clk);
    if (!owner) begin
      c0_req_valid = 1'b1; c0_req_write = write; c0_req_addr = addr; c0_req_wdata = wdata;
      do @(posedge clk); while (!c0_req_ready);
      @(negedge clk); c0_req_valid = 1'b0;
      do @(posedge clk); while (!c0_rsp_valid);
      observed_valid = c0_rsp_valid; observed = c0_rsp_rdata;
    end else begin
      c1_req_valid = 1'b1; c1_req_write = write; c1_req_addr = addr; c1_req_wdata = wdata;
      do @(posedge clk); while (!c1_req_ready);
      @(negedge clk); c1_req_valid = 1'b0;
      do @(posedge clk); while (!c1_rsp_valid);
      observed_valid = c1_rsp_valid; observed = c1_rsp_rdata;
    end
    checks++;
    if (!observed_valid || observed !== expected) begin
      failures++;
      $display("CHECK|name=%s|status=FAIL|expected=%08x|observed=%08x", name, expected, observed);
    end else begin
      $display("CHECK|name=%s|status=PASS|expected=%08x|observed=%08x", name, expected, observed);
    end
    @(posedge clk);
  endtask

  initial begin
    c0_req_valid = 0; c0_req_write = 0; c0_req_addr = 0; c0_req_wdata = 0;
    c1_req_valid = 0; c1_req_write = 0; c1_req_addr = 0; c1_req_wdata = 0;
    c0_rsp_ready = 1; c1_rsp_ready = 1;
    mem_init_valid = 0; mem_init_addr = 0; mem_init_data = 0;
    repeat (4) @(posedge clk); rst_n = 1;

    initialize_word(32'h0000_0000, 32'h1111_0000);
    initialize_word(32'h0000_0004, 32'h2222_0001);
    initialize_word(32'h0000_0008, 32'h3333_0002);
    initialize_word(32'h0000_0080, 32'h8888_0080);

    access(0, 0, 32'h0, 32'h0, 32'h1111_0000, "cold_read_c0");
    access(1, 0, 32'h0, 32'h0, 32'h1111_0000, "shared_read_c1");
    access(0, 1, 32'h0, 32'haaaa_0001, 32'haaaa_0001, "shared_to_modified");
    access(1, 0, 32'h0, 32'h0, 32'haaaa_0001, "dirty_intervention");
    access(1, 1, 32'h0, 32'hbbbb_0002, 32'hbbbb_0002, "write_invalidation");
    access(0, 0, 32'h0, 32'h0, 32'hbbbb_0002, "post_invalidation_read");
    access(0, 1, 32'h0, 32'hcccc_0003, 32'hcccc_0003, "dirty_owner_setup");
    access(0, 1, 32'h80, 32'hdddd_0080, 32'hdddd_0080, "dirty_conflict_evict");
    access(1, 0, 32'h0, 32'h0, 32'hcccc_0003, "eviction_writeback_visible");

    // Both requests are offered together. Round-robin must serialize them without loss.
    @(negedge clk);
    c0_req_valid = 1; c0_req_write = 0; c0_req_addr = 4; c0_req_wdata = 0;
    c1_req_valid = 1; c1_req_write = 0; c1_req_addr = 8; c1_req_wdata = 0;
    wait (c0_req_ready || c1_req_ready);
    @(posedge clk);
    if (c0_req_ready) begin
      @(negedge clk); c0_req_valid = 0;
      wait (c0_rsp_valid); checks++;
      if (c0_rsp_rdata !== 32'h2222_0001) begin failures++; $display("CHECK|name=simultaneous_c0|status=FAIL"); end
      else $display("CHECK|name=simultaneous_c0|status=PASS");
      wait (c1_req_ready); @(posedge clk); @(negedge clk); c1_req_valid = 0;
      wait (c1_rsp_valid); checks++;
      if (c1_rsp_rdata !== 32'h3333_0002) begin failures++; $display("CHECK|name=simultaneous_c1|status=FAIL"); end
      else $display("CHECK|name=simultaneous_c1|status=PASS");
    end else begin
      @(negedge clk); c1_req_valid = 0;
      wait (c1_rsp_valid); checks++;
      if (c1_rsp_rdata !== 32'h3333_0002) begin failures++; $display("CHECK|name=simultaneous_c1|status=FAIL"); end
      else $display("CHECK|name=simultaneous_c1|status=PASS");
      wait (c0_req_ready); @(posedge clk); @(negedge clk); c0_req_valid = 0;
      wait (c0_rsp_valid); checks++;
      if (c0_rsp_rdata !== 32'h2222_0001) begin failures++; $display("CHECK|name=simultaneous_c0|status=FAIL"); end
      else $display("CHECK|name=simultaneous_c0|status=PASS");
    end

    repeat (3) @(posedge clk);
    checks += 5;
    if (stat_read_miss < 4) begin failures++; $display("CHECK|name=read_miss_counter|status=FAIL"); end
    else $display("CHECK|name=read_miss_counter|status=PASS");
    if (stat_write_miss < 1) begin failures++; $display("CHECK|name=write_miss_counter|status=FAIL"); end
    else $display("CHECK|name=write_miss_counter|status=PASS");
    if (stat_invalidations < 2) begin failures++; $display("CHECK|name=invalidation_counter|status=FAIL"); end
    else $display("CHECK|name=invalidation_counter|status=PASS");
    if (stat_interventions < 2) begin failures++; $display("CHECK|name=intervention_counter|status=FAIL"); end
    else $display("CHECK|name=intervention_counter|status=PASS");
    if (stat_dirty_writebacks < 1) begin failures++; $display("CHECK|name=writeback_counter|status=FAIL"); end
    else $display("CHECK|name=writeback_counter|status=PASS");

    $display("SUMMARY|checks=%0d|failures=%0d|read_miss=%0d|write_miss=%0d|invalidations=%0d|interventions=%0d|writebacks=%0d",
      checks, failures, stat_read_miss, stat_write_miss, stat_invalidations,
      stat_interventions, stat_dirty_writebacks);
    if (failures != 0) $fatal(1, "MSI coherence checks failed");
    $finish;
  end
endmodule
