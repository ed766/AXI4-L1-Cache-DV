`timescale 1ns/1ps

module dual_rv32_coherent_top #(
  parameter int STORE_DRAIN_DELAY = 3,
  parameter bit SERIALIZE_STORES = 1'b0
) (
  input  logic clk,
  input  logic rst_n,
  input  logic mem_init_valid,
  input  logic [31:0] mem_init_addr,
  input  logic [31:0] mem_init_data,
  input  logic [1:0] issue_enable,
  input  logic [1:0][3:0] hart_qos,
  input  logic [7:0] axi_backpressure_percent,
  input  logic [31:0] schedule_seed,
  input  logic fault_valid,
  input  logic fault_write,
  input  logic [31:0] fault_addr,
  output logic [1:0] firmware_done,
  output logic [1:0][31:0] result_code,
  output logic [1:0][31:0] observed_value,
  output logic [1:0] store_fault_pending,
  output logic [1:0][31:0] store_fault_addr,
  output logic [1:0][1:0] sb_occupancy,
  output logic [1:0] fence_waiting,
  output logic [1:0] rvfi_valid,
  output logic [1:0][63:0] rvfi_order,
  output logic [1:0][31:0] rvfi_insn,
  output logic [1:0][31:0] rvfi_pc,
  output logic [1:0][31:0] rvfi_next_pc,
  output logic [1:0][4:0] rvfi_rd_addr,
  output logic [1:0][31:0] rvfi_rd_wdata,
  output logic [1:0] rvfi_trap,
  output logic [1:0] rvfi_intr,
  output logic [1:0][4:0] rvfi_rs1_addr,
  output logic [1:0][4:0] rvfi_rs2_addr,
  output logic [1:0][31:0] rvfi_rs1_rdata,
  output logic [1:0][31:0] rvfi_rs2_rdata,
  output logic [1:0][31:0] rvfi_mem_addr,
  output logic [1:0][3:0] rvfi_mem_rmask,
  output logic [1:0][3:0] rvfi_mem_wmask,
  output logic [1:0][31:0] rvfi_mem_rdata,
  output logic [1:0][31:0] rvfi_mem_wdata,
  output logic [1:0][31:0] rvfi_mstatus,
  output logic [1:0][31:0] rvfi_mie,
  output logic [1:0][31:0] rvfi_mtvec,
  output logic [1:0][31:0] rvfi_mscratch,
  output logic [1:0][31:0] rvfi_mepc,
  output logic [1:0][31:0] rvfi_mcause,
  output logic [1:0][31:0] rvfi_mtval,
  output logic [31:0] stat_invalidations,
  output logic [31:0] stat_interventions,
  output logic [31:0] stat_dirty_writebacks,
  output logic [31:0] stat_forwarded_loads,
  output logic [31:0] stat_bypassed_loads,
  output logic [31:0] stat_drained_stores,
  output logic [31:0] stat_axi_wait,
  output logic [31:0] stat_simultaneous_bank_cycles,
  output logic [1:0][31:0] stat_grants,
  output logic [31:0] stat_age_overrides
);
  logic [1:0] instr_ready, instr_valid, commit_valid, halted;
  logic [1:0][31:0] instr, commit_next_pc;
  logic [1:0][31:0] paddr, pwdata, prdata;
  logic [1:0] psel, penable, pwrite, pready, pslverr;
  logic [1:0] fence_done;
  logic [1:0] coh_req_valid, coh_req_ready, coh_req_write;
  logic [1:0][31:0] coh_req_addr, coh_req_wdata;
  logic [1:0] coh_rsp_valid, coh_rsp_ready;
  logic [1:0] coh_rsp_error;
  logic [1:0][31:0] coh_rsp_rdata;
  logic [1:0] home_req_valid, home_req_ready, home_req_write;
  logic [1:0][31:0] home_req_addr, home_req_wdata;
  logic [1:0] home_rsp_valid, home_rsp_ready;
  logic [1:0][31:0] home_rsp_rdata;

  for (genvar h = 0; h < 2; h++) begin : g_hart
    coherent_rv32_rom_feeder #(.HART_ID(h), .ROM_WORDS(4096)) feeder (
      .clk, .rst_n, .instr_ready(instr_ready[h]), .instr_valid(instr_valid[h]),
      .instr(instr[h]), .commit_valid(commit_valid[h]),
      .commit_next_pc(commit_next_pc[h]), .halted(halted[h]),
      .fence_done(fence_done[h]),
      .issue_enable(issue_enable[h] && (!SERIALIZE_STORES || sb_occupancy[h] == 0)),
      .fence_waiting(fence_waiting[h])
    );

    rv32_core #(
      .MMIO_BASE(32'h4000_0000), .MMIO_END(32'h8000_ffff),
      .DATA_MEM_WORDS(4096), .MAILBOX_ALIAS_BASE(32'h0001_0000),
      .ENABLE_TRAPS(1'b1), .EBREAK_TEST_HALT(1'b1)
    ) core (
      .clk, .rst_n, .instr_valid(instr_valid[h]), .instr_ready(instr_ready[h]), .instr(instr[h]),
      .irq_ext(1'b0), .irq_timer(1'b0), .paddr(paddr[h]), .psel(psel[h]),
      .penable(penable[h]), .pwrite(pwrite[h]), .pwdata(pwdata[h]),
      .prdata(prdata[h]), .pready(pready[h]), .pslverr(pslverr[h]),
      .commit_valid(commit_valid[h]), .commit_instr(), .commit_pc(),
      .commit_next_pc(commit_next_pc[h]), .wb_valid(), .wb_rd(), .wb_data(),
      .mem_valid(), .mem_write(), .mem_addr(), .mem_wdata(), .mem_rdata(),
      .branch_taken(), .illegal_instr(), .bus_error(), .retire(), .halted(halted[h]),
      .rvfi_valid(rvfi_valid[h]), .rvfi_order(rvfi_order[h]), .rvfi_insn(rvfi_insn[h]),
      .rvfi_trap(rvfi_trap[h]), .rvfi_intr(rvfi_intr[h]), .rvfi_pc_rdata(rvfi_pc[h]),
      .rvfi_pc_wdata(rvfi_next_pc[h]), .rvfi_rs1_addr(rvfi_rs1_addr[h]),
      .rvfi_rs2_addr(rvfi_rs2_addr[h]), .rvfi_rs1_rdata(rvfi_rs1_rdata[h]),
      .rvfi_rs2_rdata(rvfi_rs2_rdata[h]), .rvfi_rd_addr(rvfi_rd_addr[h]),
      .rvfi_rd_wdata(rvfi_rd_wdata[h]),
      .rvfi_mem_addr(rvfi_mem_addr[h]), .rvfi_mem_rmask(rvfi_mem_rmask[h]),
      .rvfi_mem_wmask(rvfi_mem_wmask[h]), .rvfi_mem_rdata(rvfi_mem_rdata[h]),
      .rvfi_mem_wdata(rvfi_mem_wdata[h]), .rvfi_mstatus(rvfi_mstatus[h]),
      .rvfi_mie(rvfi_mie[h]), .rvfi_mtvec(rvfi_mtvec[h]),
      .rvfi_mscratch(rvfi_mscratch[h]), .rvfi_mscratch_state(), .rvfi_mepc(rvfi_mepc[h]),
      .rvfi_mcause(rvfi_mcause[h]), .rvfi_mtval(rvfi_mtval[h])
    );
  end

  dual_hart_apb_store_buffer #(.STORE_DRAIN_DELAY(STORE_DRAIN_DELAY)) bridge (
    .clk, .rst_n, .paddr, .psel, .penable, .pwrite, .pwdata, .prdata, .pready, .pslverr,
    .coh_req_valid, .coh_req_ready, .coh_req_write, .coh_req_addr, .coh_req_wdata,
    .coh_rsp_valid, .coh_rsp_ready, .coh_rsp_rdata, .coh_rsp_error,
    .fence_done, .sb_occupancy, .result_code, .firmware_done, .observed_value,
    .store_fault_pending, .store_fault_addr, .stat_forwarded_loads, .stat_bypassed_loads,
    .stat_drained_stores
  );

  coherent_axi_qos_transport transport (
    .clk, .rst_n, .client_req_valid(coh_req_valid), .client_req_ready(coh_req_ready),
    .client_req_write(coh_req_write), .client_req_addr(coh_req_addr),
    .client_req_wdata(coh_req_wdata), .client_rsp_valid(coh_rsp_valid),
    .client_rsp_ready(coh_rsp_ready), .client_rsp_rdata(coh_rsp_rdata),
    .client_rsp_error(coh_rsp_error), .hart_qos, .backpressure_percent(axi_backpressure_percent),
    .schedule_seed, .fault_valid, .fault_write, .fault_addr,
    .home_req_valid, .home_req_ready, .home_req_write, .home_req_addr,
    .home_req_wdata, .home_rsp_valid, .home_rsp_ready, .home_rsp_rdata,
    .stat_axi_arbitration_wait(stat_axi_wait),
    .stat_simultaneous_bank_cycles, .stat_grants, .stat_age_overrides
  );

  banked_msi_home #(.LINES_PER_BANK(8), .WORDS_PER_LINE(4), .MEM_WORDS(16384)) home (
    .clk, .rst_n, .req_valid(home_req_valid), .req_ready(home_req_ready),
    .req_write(home_req_write), .req_addr(home_req_addr), .req_wdata(home_req_wdata),
    .rsp_valid(home_rsp_valid), .rsp_ready(home_rsp_ready), .rsp_rdata(home_rsp_rdata),
    .mem_init_valid, .mem_init_addr, .mem_init_data, .stat_invalidations,
    .stat_interventions, .stat_dirty_writebacks
  );

`ifndef SYNTHESIS
  a_no_dual_firmware_completion_x: assert property (@(posedge clk) disable iff (!rst_n)
    !$isunknown(firmware_done));
  for (genvar h = 0; h < 2; h++) begin : g_top_assertions
    a_fence_instruction_waits: assert property (@(posedge clk) disable iff (!rst_n)
      fence_waiting[h] |-> !instr_valid[h]);
    a_retired_fence_after_drain: assert property (@(posedge clk) disable iff (!rst_n)
      rvfi_valid[h] && rvfi_insn[h][6:0] == 7'b0001111 &&
      rvfi_insn[h][14:12] == 3'b000 |-> fence_done[h]);
  end
`endif
endmodule
