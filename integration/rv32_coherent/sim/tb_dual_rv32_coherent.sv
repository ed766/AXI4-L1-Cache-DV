`timescale 1ns/1ps

module tb_dual_rv32_coherent #(
  parameter int STORE_DRAIN_DELAY = 3,
  parameter bit SERIALIZE_STORES = 1'b0
);
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic mem_init_valid;
  logic [31:0] mem_init_addr, mem_init_data;
  logic [1:0] issue_enable;
  logic [1:0][3:0] hart_qos;
  logic [7:0] axi_backpressure_percent;
  logic [31:0] schedule_seed;
  logic fault_valid, fault_write;
  logic [31:0] fault_addr;
  logic [1:0] firmware_done;
  logic [1:0][31:0] result_code;
  logic [1:0][31:0] observed_value;
  logic [1:0] store_fault_pending;
  logic [1:0][31:0] store_fault_addr;
  logic [1:0][1:0] sb_occupancy;
  logic [1:0] fence_waiting, rvfi_valid;
  logic [1:0][63:0] rvfi_order;
  logic [1:0][31:0] rvfi_insn, rvfi_pc, rvfi_next_pc, rvfi_mem_addr;
  logic [1:0][4:0] rvfi_rd_addr;
  logic [1:0][31:0] rvfi_rd_wdata;
  logic [1:0] rvfi_trap, rvfi_intr;
  logic [1:0][4:0] rvfi_rs1_addr, rvfi_rs2_addr;
  logic [1:0][31:0] rvfi_rs1_rdata, rvfi_rs2_rdata;
  logic [1:0][3:0] rvfi_mem_rmask, rvfi_mem_wmask;
  logic [1:0][31:0] rvfi_mem_rdata, rvfi_mem_wdata;
  logic [1:0][31:0] rvfi_mstatus, rvfi_mie, rvfi_mtvec, rvfi_mscratch;
  logic [1:0][31:0] rvfi_mepc, rvfi_mcause, rvfi_mtval;
  logic [31:0] stat_invalidations, stat_interventions, stat_dirty_writebacks;
  logic [31:0] stat_forwarded_loads, stat_bypassed_loads, stat_drained_stores;
  logic [31:0] stat_axi_wait, stat_simultaneous_bank_cycles, stat_age_overrides;
  logic [1:0][31:0] stat_grants;
  logic [31:0] issue_lfsr;
  logic run_enable;
  integer trace_fd, event_fd;
  integer cycles;
  integer issue_stall_percent, reset_cycle, reset_hold, epoch, drain_wait_cycles;
  integer qos0, qos1, fault_valid_arg, fault_write_arg;
  string trace_file, event_trace_file;

  dual_rv32_coherent_top #(
    .STORE_DRAIN_DELAY(STORE_DRAIN_DELAY), .SERIALIZE_STORES(SERIALIZE_STORES)
  ) dut (.*);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      issue_lfsr <= schedule_seed ^ 32'h9e37_79b9;
      issue_enable <= '0;
    end else begin
      issue_lfsr <= {issue_lfsr[30:0],
                     issue_lfsr[31] ^ issue_lfsr[21] ^ issue_lfsr[1] ^ issue_lfsr[0]};
      issue_enable[0] <= run_enable && ((int'(issue_lfsr[7:0]) % 100) >= issue_stall_percent);
      issue_enable[1] <= run_enable && ((int'(issue_lfsr[15:8]) % 100) >= issue_stall_percent);
    end
  end

  always @(posedge clk) begin
    if (rst_n && event_fd != 0) begin
      for (int h = 0; h < 2; h++) begin
        if (dut.bridge.psel[h] && dut.bridge.penable[h] && dut.bridge.pready[h])
          $fwrite(event_fd, "%0d,%0d,apb_accept,%0d,%0d,%08x,%08x,%0d,%0d\n",
                  cycles, epoch, h, dut.bridge.paddr[h][4], dut.bridge.paddr[h],
                  dut.bridge.pwrite[h] ? dut.bridge.pwdata[h] : dut.bridge.prdata[h],
                  dut.bridge.pwrite[h], dut.bridge.pslverr[h]);
        if (fence_waiting[h])
          $fwrite(event_fd, "%0d,%0d,fence_wait,%0d,-1,00000000,00000000,%0d,0\n",
                  cycles, epoch, h, sb_occupancy[h]);
        if (dut.bridge.enqueue[h])
          $fwrite(event_fd, "%0d,%0d,store_enqueue,%0d,%0d,%08x,%08x,%0d,%0d\n",
                  cycles, epoch, h, dut.bridge.paddr[h][4], dut.bridge.paddr[h],
                  dut.bridge.pwdata[h], dut.bridge.sb_count[h] + 1'b1, 0);
        if (dut.bridge.store_complete[h])
          $fwrite(event_fd, "%0d,%0d,store_drain,%0d,%0d,%08x,%08x,%0d,%0d\n",
                  cycles, epoch, h, dut.bridge.sb_addr[h][dut.bridge.sb_head[h]][4],
                  dut.bridge.sb_addr[h][dut.bridge.sb_head[h]],
                  dut.bridge.sb_data[h][dut.bridge.sb_head[h]], dut.bridge.sb_count[h],
                  dut.bridge.coh_rsp_error[h]);
        if (dut.bridge.psel[h] && dut.bridge.penable[h] && !dut.bridge.pwrite[h] &&
            dut.bridge.shared_access[h] && dut.bridge.forwarded[h] && dut.bridge.pready[h])
          $fwrite(event_fd, "%0d,%0d,load_forward,%0d,%0d,%08x,%08x,%0d,0\n",
                  cycles, epoch, h, dut.bridge.paddr[h][4], dut.bridge.paddr[h],
                  dut.bridge.forwarded_data[h], dut.bridge.sb_count[h]);
        if (dut.transport.client_req_valid[h] && dut.transport.client_req_ready[h])
          $fwrite(event_fd, "%0d,%0d,fabric_request,%0d,%0d,%08x,%08x,%0d,%0d\n",
                  cycles, epoch, h, dut.transport.client_req_addr[h][4],
                  dut.transport.client_req_addr[h], dut.transport.client_req_wdata[h],
                  dut.transport.client_req_write[h], sb_occupancy[h]);
        if (dut.transport.client_rsp_valid[h] && dut.transport.client_rsp_ready[h])
          $fwrite(event_fd, "%0d,%0d,fabric_response,%0d,-1,00000000,%08x,0,%0d\n",
                  cycles, epoch, h, dut.transport.client_rsp_rdata[h],
                  dut.transport.client_rsp_error[h]);
      end
      for (int h = 0; h < 2; h++) begin
        if (dut.home_req_valid[h] && dut.home_req_ready[h])
          $fwrite(event_fd, "%0d,%0d,bank_request,%0d,%0d,%08x,%08x,%0d,0\n",
                  cycles, epoch, h, dut.home_req_addr[h][4], dut.home_req_addr[h],
                  dut.home_req_wdata[h], dut.home_req_write[h]);
      end
      if (dut.transport.tstate[0] != 0 && dut.transport.tstate[1] != 0)
        $fwrite(event_fd, "%0d,%0d,simultaneous_banks,-1,-1,00000000,00000000,0,0\n",
                cycles, epoch);
      if (|dut.transport.mon_ar_age_override || |dut.transport.mon_aw_age_override)
        $fwrite(event_fd, "%0d,%0d,qos_age_override,-1,-1,00000000,00000000,0,0\n",
                cycles, epoch);
    end
  end

  initial begin
    trace_file = "coherent_trace.csv";
    event_trace_file = "coherent_events.csv";
    void'($value$plusargs("TRACE_FILE=%s", trace_file));
    void'($value$plusargs("EVENT_TRACE_FILE=%s", event_trace_file));
    schedule_seed = 32'h1;
    issue_stall_percent = 0;
    axi_backpressure_percent = 0;
    qos0 = 4; qos1 = 8;
    fault_valid_arg = 0; fault_write_arg = 0; fault_addr = '0;
    reset_cycle = -1; reset_hold = 3;
    void'($value$plusargs("SCHEDULE_SEED=%d", schedule_seed));
    void'($value$plusargs("ISSUE_STALL_PERCENT=%d", issue_stall_percent));
    void'($value$plusargs("AXI_BACKPRESSURE_PERCENT=%d", axi_backpressure_percent));
    void'($value$plusargs("QOS0=%d", qos0));
    void'($value$plusargs("QOS1=%d", qos1));
    void'($value$plusargs("FAULT_VALID=%d", fault_valid_arg));
    void'($value$plusargs("FAULT_WRITE=%d", fault_write_arg));
    void'($value$plusargs("FAULT_ADDR=%h", fault_addr));
    void'($value$plusargs("RESET_CYCLE=%d", reset_cycle));
    void'($value$plusargs("RESET_HOLD=%d", reset_hold));
    hart_qos[0] = qos0[3:0]; hart_qos[1] = qos1[3:0];
    fault_valid = fault_valid_arg != 0; fault_write = fault_write_arg != 0;
    run_enable = 1'b0; epoch = 0; cycles = 0;
    trace_fd = $fopen(trace_file, "w");
    event_fd = $fopen(event_trace_file, "w");
    $fwrite(trace_fd, "cycle,event,hart,epoch,order,insn,trap,intr,pc_rdata,pc_wdata,rs1_addr,rs2_addr,rs1_rdata,rs2_rdata,rd_addr,rd_wdata,mem_addr,mem_rmask,mem_wmask,mem_rdata,mem_wdata,mstatus,mie,mtvec,mscratch,mepc,mcause,mtval,irq_level,irq_timer_level,sb0,sb1\n");
    $fwrite(event_fd, "cycle,epoch,event,hart,bank,address,data,detail0,detail1\n");
    mem_init_valid = 1'b0;
    mem_init_addr = '0;
    mem_init_data = '0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    epoch = 1;
    $fwrite(event_fd, "0,1,reset_release,-1,-1,00000000,00000000,0,0\n");
    for (int word = 0; word < 8; word++) begin
      @(negedge clk);
      mem_init_valid = 1'b1;
      mem_init_addr = word * 4;
      mem_init_data = '0;
      $fwrite(event_fd, "%0d,%0d,memory_init,-1,%0d,%08x,%08x,0,0\n",
              cycles, epoch, mem_init_addr[4], mem_init_addr, mem_init_data);
      @(negedge clk);
      mem_init_valid = 1'b0;
    end
    run_enable = 1'b1;
    while (!(firmware_done[0] && firmware_done[1]) && cycles < 20000) begin
      @(posedge clk);
      cycles++;
      if (cycles == reset_cycle) begin
        run_enable = 1'b0;
        rst_n = 1'b0;
        $fwrite(event_fd, "%0d,%0d,reset_assert,-1,-1,00000000,00000000,0,0\n", cycles, epoch);
        repeat (reset_hold) @(posedge clk);
        rst_n = 1'b1;
        epoch++;
        $fwrite(event_fd, "%0d,%0d,reset_release,-1,-1,00000000,00000000,0,0\n", cycles, epoch);
        run_enable = 1'b1;
      end
      for (int h = 0; h < 2; h++) begin
        if (rvfi_valid[h])
          $fwrite(trace_fd, "%0d,retire,%0d,0,%0d,%08x,%0d,%0d,%08x,%08x,%0d,%0d,%08x,%08x,%0d,%08x,%08x,%x,%x,%08x,%08x,%08x,%08x,%08x,%08x,%08x,%08x,%08x,0,0,%0d,%0d\n",
                  cycles, h, rvfi_order[h], rvfi_insn[h], rvfi_trap[h], rvfi_intr[h],
                  rvfi_pc[h], rvfi_next_pc[h], rvfi_rs1_addr[h], rvfi_rs2_addr[h],
                  rvfi_rs1_rdata[h], rvfi_rs2_rdata[h], rvfi_rd_addr[h], rvfi_rd_wdata[h],
                  rvfi_mem_addr[h], rvfi_mem_rmask[h], rvfi_mem_wmask[h],
                  rvfi_mem_rdata[h], rvfi_mem_wdata[h], rvfi_mstatus[h], rvfi_mie[h],
                  rvfi_mtvec[h], rvfi_mscratch[h], rvfi_mepc[h], rvfi_mcause[h], rvfi_mtval[h],
                  sb_occupancy[0], sb_occupancy[1]);
        if (fence_waiting[h])
          $fwrite(trace_fd, "%0d,fence_wait,%0d,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,%0d,%0d\n",
                  cycles, h, sb_occupancy[0], sb_occupancy[1]);
      end
    end
    // The completion mailbox is uncached; under heavy backpressure it can be
    // written before an older buffered shared store reaches the home agent.
    drain_wait_cycles = 0;
    while ((|sb_occupancy) && drain_wait_cycles < 2000) begin
      @(posedge clk);
      cycles++;
      drain_wait_cycles++;
    end
    repeat (20) begin
      @(posedge clk);
      cycles++;
    end
    // Snapshot the physical backing stores and both private MSI line arrays.
    // The independent replay compares this state instead of relying only on
    // values that firmware happened to read back during the scenario.
    for (int word = 0; word < 64; word++) begin
      if (((word * 4) & 32'h10) != 0)
        $fwrite(event_fd, "%0d,%0d,final_backing,-1,1,%08x,%08x,0,0\n",
                cycles, epoch, word * 4, dut.home.g_bank[1].home_bank.backing_mem[word]);
      else
        $fwrite(event_fd, "%0d,%0d,final_backing,-1,0,%08x,%08x,0,0\n",
                cycles, epoch, word * 4, dut.home.g_bank[0].home_bank.backing_mem[word]);
    end
    for (int line = 0; line < 8; line++) begin
      for (int word = 0; word < 4; word++) begin
        for (int h = 0; h < 2; h++) begin
          $fwrite(event_fd, "%0d,%0d,final_line,%0d,0,%08x,%08x,%0d,%0d\n",
                  cycles, epoch, h, dut.home.g_bank[0].home_bank.line_tag[h][line],
                  dut.home.g_bank[0].home_bank.line_data[h][line][word],
                  dut.home.g_bank[0].home_bank.line_state[h][line], line * 4 + word);
          $fwrite(event_fd, "%0d,%0d,final_line,%0d,1,%08x,%08x,%0d,%0d\n",
                  cycles, epoch, h, dut.home.g_bank[1].home_bank.line_tag[h][line],
                  dut.home.g_bank[1].home_bank.line_data[h][line][word],
                  dut.home.g_bank[1].home_bank.line_state[h][line], line * 4 + word);
        end
      end
    end
    $fclose(trace_fd);
    $fclose(event_fd);
    $display("COHERENT_SUMMARY|cycles=%0d|done0=%0d|done1=%0d|result0=%08x|result1=%08x|observed0=%08x|observed1=%08x|forwarded=%0d|bypassed=%0d|drained=%0d|invalidations=%0d|interventions=%0d|writebacks=%0d|axi_wait=%0d|simultaneous_banks=%0d|grants0=%0d|grants1=%0d|age_overrides=%0d|fault0=%0d|fault1=%0d|epoch=%0d",
      cycles, firmware_done[0], firmware_done[1], result_code[0], result_code[1],
      observed_value[0], observed_value[1],
      stat_forwarded_loads, stat_bypassed_loads, stat_drained_stores,
      stat_invalidations, stat_interventions, stat_dirty_writebacks, stat_axi_wait,
      stat_simultaneous_bank_cycles, stat_grants[0], stat_grants[1], stat_age_overrides,
      store_fault_pending[0], store_fault_pending[1], epoch);
    if (!(firmware_done[0] && firmware_done[1])) $fatal(1, "firmware timeout");
    if (|sb_occupancy) $fatal(1, "store-buffer drain timeout");
    if ((result_code[0] != 0) || (result_code[1] != 0)) $fatal(1, "firmware failure");
    $finish;
  end
endmodule
