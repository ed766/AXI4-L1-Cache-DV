`timescale 1ns/1ps

// Synthesizable March C-minus SRAM wrapper used as optional DFT collateral.
module cache_sram_bist #(
  parameter int WORDS = 64,
  parameter int DATA_W = 32
) (
  input  logic                       clk,
  input  logic                       rst_n,
  input  logic                       start,
  output logic                       busy,
  output logic                       done,
  output logic                       fail,
  output logic [$clog2(WORDS)-1:0]   fail_addr,
  output logic [DATA_W-1:0]          fail_expected,
  output logic [DATA_W-1:0]          fail_observed,

  input  logic                       functional_write,
  input  logic [$clog2(WORDS)-1:0]   functional_addr,
  input  logic [DATA_W-1:0]          functional_wdata,
  output logic [DATA_W-1:0]          functional_rdata,

  input  logic                       fault_enable,
  input  logic [$clog2(WORDS)-1:0]   fault_addr,
  input  logic [$clog2(DATA_W)-1:0]  fault_bit,
  input  logic                       fault_stuck_value
);
  localparam int ADDR_W = $clog2(WORDS);
  typedef enum logic [3:0] {
    BIST_IDLE, BIST_W0_UP, BIST_R0W1_UP, BIST_R1W0_UP,
    BIST_R0W1_DOWN, BIST_R1W0_DOWN, BIST_R0_DOWN, BIST_FINISH
  } bist_state_e;
  bist_state_e state;
  logic [$clog2(WORDS)-1:0] address;
  logic [DATA_W-1:0] memory [0:WORDS-1];
  logic functional_write_applied;

  function automatic logic [DATA_W-1:0] faulted_value(
    input logic [DATA_W-1:0] raw,
    input logic [$clog2(WORDS)-1:0] addr
  );
    logic [DATA_W-1:0] value;
    value = raw;
    if (fault_enable && addr == fault_addr)
      value[fault_bit] = fault_stuck_value;
    faulted_value = value;
  endfunction

  wire [DATA_W-1:0] observed = faulted_value(memory[address], address);
  assign functional_rdata = faulted_value(memory[functional_addr], functional_addr);
  assign busy = state != BIST_IDLE && state != BIST_FINISH;

  task automatic record_mismatch(input logic [DATA_W-1:0] expected);
    if (!fail && observed !== expected) begin
      fail <= 1'b1;
      fail_addr <= address;
      fail_expected <= expected;
      fail_observed <= observed;
    end
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= BIST_IDLE;
      address <= '0;
      done <= 1'b0;
      fail <= 1'b0;
      fail_addr <= '0;
      fail_expected <= '0;
      fail_observed <= '0;
      functional_write_applied <= 1'b0;
    end else begin
      done <= 1'b0;
      functional_write_applied <= 1'b0;
      if (functional_write && !busy) begin
        functional_write_applied <= 1'b1;
        memory[functional_addr] <= functional_wdata;
        if (fault_enable && functional_addr == fault_addr)
          memory[functional_addr][fault_bit] <= fault_stuck_value;
      end
      case (state)
        BIST_IDLE: if (start) begin
          address <= '0;
          fail <= 1'b0;
          fail_addr <= '0;
          fail_expected <= '0;
          fail_observed <= '0;
          state <= BIST_W0_UP;
        end
        BIST_W0_UP: begin
          memory[address] <= '0;
          if (fault_enable && address == fault_addr)
            memory[address][fault_bit] <= fault_stuck_value;
          if (address == ADDR_W'(WORDS-1)) begin address <= '0; state <= BIST_R0W1_UP; end
          else address <= address + 1'b1;
        end
        BIST_R0W1_UP: begin
          record_mismatch('0);
          memory[address] <= '1;
          if (fault_enable && address == fault_addr)
            memory[address][fault_bit] <= fault_stuck_value;
          if (address == ADDR_W'(WORDS-1)) begin address <= '0; state <= BIST_R1W0_UP; end
          else address <= address + 1'b1;
        end
        BIST_R1W0_UP: begin
          record_mismatch('1);
          memory[address] <= '0;
          if (fault_enable && address == fault_addr)
            memory[address][fault_bit] <= fault_stuck_value;
          if (address == ADDR_W'(WORDS-1)) begin address <= ADDR_W'(WORDS-1); state <= BIST_R0W1_DOWN; end
          else address <= address + 1'b1;
        end
        BIST_R0W1_DOWN: begin
          record_mismatch('0);
          memory[address] <= '1;
          if (fault_enable && address == fault_addr)
            memory[address][fault_bit] <= fault_stuck_value;
          if (address == 0) begin address <= ADDR_W'(WORDS-1); state <= BIST_R1W0_DOWN; end
          else address <= address - 1'b1;
        end
        BIST_R1W0_DOWN: begin
          record_mismatch('1);
          memory[address] <= '0;
          if (fault_enable && address == fault_addr)
            memory[address][fault_bit] <= fault_stuck_value;
          if (address == 0) begin address <= ADDR_W'(WORDS-1); state <= BIST_R0_DOWN; end
          else address <= address - 1'b1;
        end
        BIST_R0_DOWN: begin
          record_mismatch('0);
          if (address == 0) state <= BIST_FINISH;
          else address <= address - 1'b1;
        end
        BIST_FINISH: begin
          done <= 1'b1;
          state <= BIST_IDLE;
        end
        default: state <= BIST_IDLE;
      endcase
    end
  end

`ifndef SYNTHESIS
  a_done_not_busy: assert property (@(posedge clk) done |-> !busy);
  a_fail_metadata_stable: assert property (@(posedge clk) disable iff (!rst_n)
    fail && busy |=> fail_addr == $past(fail_addr));
  a_functional_write_blocked_during_bist: assert property (@(posedge clk) disable iff (!rst_n)
    busy |-> !functional_write_applied);
`endif

  initial begin
    if ((WORDS & (WORDS - 1)) != 0) $fatal(1, "WORDS must be a power of two");
    if ((DATA_W & (DATA_W - 1)) != 0) $fatal(1, "DATA_W must be a power of two");
  end
endmodule
