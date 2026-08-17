`timescale 1ns/1ps

module tb_cache_sram_bist;
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;
  logic start, busy, done, fail;
  logic [5:0] fail_addr, functional_addr, fault_addr;
  logic [31:0] fail_expected, fail_observed;
  logic functional_write;
  logic [31:0] functional_wdata, functional_rdata;
  logic fault_enable, fault_stuck_value;
  logic [4:0] fault_bit;
  integer checks = 0;
  integer failures = 0;

  cache_sram_bist dut (.*);

  task automatic run_bist(
    input bit enable_fault,
    input logic [5:0] address_fault,
    input logic [4:0] bit_fault,
    input bit stuck_value,
    input bit expect_fail,
    input string name
  );
    fault_enable = enable_fault;
    fault_addr = address_fault;
    fault_bit = bit_fault;
    fault_stuck_value = stuck_value;
    @(negedge clk); start = 1;
    @(posedge clk); @(negedge clk); start = 0;
    wait (done);
    checks++;
    if (fail !== expect_fail || (expect_fail && fail_addr !== address_fault)) begin
      failures++;
      $display("CHECK|name=%s|status=FAIL|fail=%0d|addr=%0d|expected_addr=%0d", name, fail, fail_addr, address_fault);
    end else begin
      $display("CHECK|name=%s|status=PASS|fail=%0d|addr=%0d", name, fail, fail_addr);
    end
    @(posedge clk);
  endtask

  initial begin
    start = 0; functional_write = 0; functional_addr = 0; functional_wdata = 0;
    fault_enable = 0; fault_addr = 0; fault_bit = 0; fault_stuck_value = 0;
    repeat (4) @(posedge clk); rst_n = 1;

    run_bist(0, 0, 0, 0, 0, "clean_march_c_minus");
    run_bist(1, 0, 0, 0, 1, "stuck_at_zero_first_address");
    run_bist(1, 63, 31, 1, 1, "stuck_at_one_last_address");
    run_bist(1, 32, 15, 0, 1, "stuck_at_zero_middle_address");

    fault_enable = 0;
    @(negedge clk); functional_write = 1; functional_addr = 6'd9; functional_wdata = 32'h1234_abcd;
    @(posedge clk); @(negedge clk); functional_write = 0;
    checks++;
    if (functional_rdata !== 32'h1234_abcd) begin failures++; $display("CHECK|name=functional_port|status=FAIL"); end
    else $display("CHECK|name=functional_port|status=PASS");

    @(negedge clk); start = 1;
    @(posedge clk); @(negedge clk); start = 0;
    wait (busy);
    functional_write = 1; functional_addr = 6'd9; functional_wdata = 32'hdead_beef;
    repeat (2) @(posedge clk);
    @(negedge clk); functional_write = 0;
    wait (done); @(posedge clk);
    checks++;
    if (fail) begin failures++; $display("CHECK|name=busy_owns_sram_port|status=FAIL"); end
    else $display("CHECK|name=busy_owns_sram_port|status=PASS");

    @(negedge clk); rst_n = 0; repeat (2) @(posedge clk); rst_n = 1; @(posedge clk);
    checks++;
    if (busy || done || fail) begin failures++; $display("CHECK|name=reset_clears_status|status=FAIL"); end
    else $display("CHECK|name=reset_clears_status|status=PASS");

    $display("SUMMARY|checks=%0d|failures=%0d", checks, failures);
    if (failures != 0) $fatal(1, "SRAM BIST checks failed");
    $finish;
  end
endmodule
