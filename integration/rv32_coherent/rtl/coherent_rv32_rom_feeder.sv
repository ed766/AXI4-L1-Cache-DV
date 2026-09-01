module coherent_rv32_rom_feeder #(
  parameter int HART_ID = 0,
  parameter int ROM_WORDS = 4096
) (
  input  logic clk,
  input  logic rst_n,
  input  logic instr_ready,
  output logic instr_valid,
  output logic [31:0] instr,
  input  logic commit_valid,
  input  logic [31:0] commit_next_pc,
  input  logic halted,
  input  logic fence_done,
  input  logic issue_enable,
  output logic fence_waiting
);
  logic [31:0] rom [0:ROM_WORDS-1];
  logic [31:0] fetch_pc_q;
  logic wait_commit_q;
  logic is_fence;
  string firmware_hex;

  initial begin
    for (int idx = 0; idx < ROM_WORDS; idx++) rom[idx] = 32'h0010_0073;
    firmware_hex = "";
    if (HART_ID == 0) void'($value$plusargs("HART0_HEX=%s", firmware_hex));
    else void'($value$plusargs("HART1_HEX=%s", firmware_hex));
    if (firmware_hex == "") $fatal(1, "missing HART%0d_HEX plusarg", HART_ID);
    $readmemh(firmware_hex, rom);
  end

  assign instr = rom[(fetch_pc_q >> 2) % ROM_WORDS];
  // Match every legal FENCE predecessor/successor mask, not only the
  // zero-mask assembly spelling. GCC normally emits `fence rw,rw`.
  assign is_fence = instr[6:0] == 7'b0001111 && instr[14:12] == 3'b000;
`ifdef COH_MUT_EARLY_FENCE
  assign fence_waiting = 1'b0;
`else
  assign fence_waiting = is_fence && !fence_done;
`endif
  assign instr_valid = rst_n && issue_enable && !halted && !wait_commit_q &&
                       !commit_valid && !fence_waiting;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fetch_pc_q <= '0;
      wait_commit_q <= 1'b0;
    end else begin
      if (commit_valid) begin
        fetch_pc_q <= commit_next_pc;
        wait_commit_q <= 1'b0;
      end
      if (instr_valid && instr_ready) wait_commit_q <= 1'b1;
    end
  end
endmodule
