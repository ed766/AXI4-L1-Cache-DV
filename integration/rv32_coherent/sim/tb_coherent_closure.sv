`timescale 1ns/1ps

module tb_coherent_closure;
  localparam logic [31:0] SHARED = 32'h8000_0000;
  localparam logic [31:0] MAILBOX = 32'h4000_0000;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic [1:0][31:0] paddr, pwdata, prdata;
  logic [1:0] psel, penable, pwrite, pready, pslverr;
  logic [1:0] coh_req_valid, coh_req_ready, coh_req_write;
  logic [1:0][31:0] coh_req_addr, coh_req_wdata;
  logic [1:0] coh_rsp_valid, coh_rsp_ready, coh_rsp_error;
  logic [1:0][31:0] coh_rsp_rdata;
  logic [1:0] fence_done, firmware_done, store_fault_pending;
  logic [1:0][1:0] sb_occupancy;
  logic [1:0][31:0] result_code, observed_value, store_fault_addr;
  logic [31:0] stat_forwarded_loads, stat_bypassed_loads, stat_drained_stores;
  logic [1:0] home_req_valid, home_req_ready, home_req_write;
  logic [1:0][31:0] home_req_addr, home_req_wdata;
  logic [1:0] home_rsp_valid, home_rsp_ready;
  logic [1:0][31:0] home_rsp_rdata;
  logic [1:0][3:0] hart_qos;
  logic [7:0] backpressure_percent;
  logic [31:0] schedule_seed;
  logic fault_valid, fault_write;
  logic [31:0] fault_addr;
  logic mem_init_valid;
  logic [31:0] mem_init_addr, mem_init_data;
  logic [31:0] stat_axi_wait, stat_simultaneous_bank_cycles, stat_age_overrides;
  logic [1:0][31:0] stat_grants;
  logic [31:0] stat_invalidations, stat_interventions, stat_dirty_writebacks;

  integer cycles, checks, failures, event_fd;
  string test_name, event_file;
  logic saw_enqueue_and_drain, saw_enqueue_and_failed_drain;

  dual_hart_apb_store_buffer #(.STORE_DRAIN_DELAY(40)) bridge (
    .clk, .rst_n, .paddr, .psel, .penable, .pwrite, .pwdata, .prdata, .pready, .pslverr,
    .coh_req_valid, .coh_req_ready, .coh_req_write, .coh_req_addr, .coh_req_wdata,
    .coh_rsp_valid, .coh_rsp_ready, .coh_rsp_rdata, .coh_rsp_error,
    .fence_done, .sb_occupancy, .result_code, .firmware_done, .observed_value,
    .store_fault_pending, .store_fault_addr, .stat_forwarded_loads,
    .stat_bypassed_loads, .stat_drained_stores
  );

  coherent_axi_qos_transport transport (
    .clk, .rst_n, .client_req_valid(coh_req_valid), .client_req_ready(coh_req_ready),
    .client_req_write(coh_req_write), .client_req_addr(coh_req_addr),
    .client_req_wdata(coh_req_wdata), .client_rsp_valid(coh_rsp_valid),
    .client_rsp_ready(coh_rsp_ready), .client_rsp_rdata(coh_rsp_rdata),
    .client_rsp_error(coh_rsp_error), .hart_qos, .backpressure_percent,
    .schedule_seed, .fault_valid, .fault_write, .fault_addr,
    .home_req_valid, .home_req_ready, .home_req_write, .home_req_addr,
    .home_req_wdata, .home_rsp_valid, .home_rsp_ready, .home_rsp_rdata,
    .stat_axi_arbitration_wait(stat_axi_wait), .stat_simultaneous_bank_cycles,
    .stat_grants, .stat_age_overrides
  );

  banked_msi_home #(.LINES_PER_BANK(8), .WORDS_PER_LINE(4), .MEM_WORDS(16384)) home (
    .clk, .rst_n, .req_valid(home_req_valid), .req_ready(home_req_ready),
    .req_write(home_req_write), .req_addr(home_req_addr), .req_wdata(home_req_wdata),
    .rsp_valid(home_rsp_valid), .rsp_ready(home_rsp_ready), .rsp_rdata(home_rsp_rdata),
    .mem_init_valid, .mem_init_addr, .mem_init_data, .stat_invalidations,
    .stat_interventions, .stat_dirty_writebacks
  );

  task automatic check(input logic condition, input string description);
    checks++;
    if (!condition) begin
      failures++;
      $display("CLOSURE_CHECK|test=%s|status=FAIL|detail=%s", test_name, description);
    end
  endtask

  task automatic apb_write(input int hart, input logic [31:0] address,
                           input logic [31:0] data, output logic error,
                           output int wait_cycles);
    @(negedge clk);
    paddr[hart] = address; pwdata[hart] = data; pwrite[hart] = 1'b1;
    psel[hart] = 1'b1; penable[hart] = 1'b0;
    @(negedge clk); penable[hart] = 1'b1; wait_cycles = 0;
    do begin
      @(posedge clk);
      if (!pready[hart]) wait_cycles++;
      if (wait_cycles > 2000) $fatal(1, "APB write timeout");
    end while (!pready[hart]);
    error = pslverr[hart];
    @(negedge clk); psel[hart] = 1'b0; penable[hart] = 1'b0; pwrite[hart] = 1'b0;
  endtask

  task automatic apb_read(input int hart, input logic [31:0] address,
                          output logic [31:0] data, output logic error,
                          output int wait_cycles);
    @(negedge clk);
    paddr[hart] = address; pwdata[hart] = '0; pwrite[hart] = 1'b0;
    psel[hart] = 1'b1; penable[hart] = 1'b0;
    @(negedge clk); penable[hart] = 1'b1; wait_cycles = 0;
    do begin
      @(posedge clk);
      if (!pready[hart]) wait_cycles++;
      if (wait_cycles > 2000) $fatal(1, "APB read timeout");
    end while (!pready[hart]);
    data = prdata[hart]; error = pslverr[hart];
    @(negedge clk); psel[hart] = 1'b0; penable[hart] = 1'b0;
  endtask

  task automatic paired_write(input logic [31:0] address0, input logic [31:0] data0,
                              input logic [31:0] address1, input logic [31:0] data1);
    @(negedge clk);
    paddr[0] = address0; pwdata[0] = data0; pwrite[0] = 1'b1;
    paddr[1] = address1; pwdata[1] = data1; pwrite[1] = 1'b1;
    psel = 2'b11; penable = 2'b00;
    @(negedge clk); penable = 2'b11;
    while (!(pready[0] && pready[1])) @(posedge clk);
    @(negedge clk); psel = '0; penable = '0; pwrite = '0;
  endtask

  task automatic wait_for_fence(input int hart);
    int timeout;
    timeout = 0;
    while (!fence_done[hart]) begin
      @(posedge clk); timeout++;
      if (timeout > 4000) $fatal(1, "fence timeout");
    end
  endtask

  task automatic wait_for_both_fences;
    int timeout;
    timeout = 0;
    while (!(fence_done[0] && fence_done[1])) begin
      @(posedge clk); timeout++;
      if (timeout > 4000) $fatal(1, "dual fence timeout");
    end
  endtask

  task automatic initialize_memory;
    for (int word = 0; word < 64; word++) begin
      @(negedge clk);
      mem_init_valid = 1'b1; mem_init_addr = word * 4; mem_init_data = '0;
      $fwrite(event_fd, "%0d,1,memory_init,-1,%0d,%08x,%08x,0,0\n",
              cycles, mem_init_addr[4], mem_init_addr, mem_init_data);
      @(negedge clk); mem_init_valid = 1'b0;
    end
  endtask

  task automatic dump_final_state;
    for (int word = 0; word < 64; word++) begin
      if (((word * 4) & 32'h10) != 0)
        $fwrite(event_fd, "%0d,1,final_backing,-1,1,%08x,%08x,0,0\n",
                cycles, word * 4, home.g_bank[1].home_bank.backing_mem[word]);
      else
        $fwrite(event_fd, "%0d,1,final_backing,-1,0,%08x,%08x,0,0\n",
                cycles, word * 4, home.g_bank[0].home_bank.backing_mem[word]);
    end
    for (int line = 0; line < 8; line++) begin
      for (int word = 0; word < 4; word++) begin
        for (int hart = 0; hart < 2; hart++) begin
          $fwrite(event_fd, "%0d,1,final_line,%0d,0,%08x,%08x,%0d,%0d\n",
                  cycles, hart, home.g_bank[0].home_bank.line_tag[hart][line],
                  home.g_bank[0].home_bank.line_data[hart][line][word],
                  home.g_bank[0].home_bank.line_state[hart][line], line * 4 + word);
          $fwrite(event_fd, "%0d,1,final_line,%0d,1,%08x,%08x,%0d,%0d\n",
                  cycles, hart, home.g_bank[1].home_bank.line_tag[hart][line],
                  home.g_bank[1].home_bank.line_data[hart][line][word],
                  home.g_bank[1].home_bank.line_state[hart][line], line * 4 + word);
        end
      end
    end
  endtask

  always @(posedge clk) begin
    if (rst_n) cycles++;
    if (rst_n && event_fd != 0) begin
      for (int hart = 0; hart < 2; hart++) begin
        if (bridge.psel[hart] && bridge.penable[hart] && !bridge.pready[hart])
          $fwrite(event_fd, "%0d,1,apb_wait,%0d,%0d,%08x,%08x,%0d,%0d\n",
                  cycles, hart, bridge.paddr[hart][4], bridge.paddr[hart], bridge.pwdata[hart],
                  bridge.pwrite[hart], bridge.sb_count[hart]);
        if (!bridge.fence_done[hart] && bridge.sb_count[hart] != 0)
          $fwrite(event_fd, "%0d,1,fence_blocked,%0d,-1,00000000,00000000,%0d,%0d\n",
                  cycles, hart, bridge.sb_count[hart], bridge.store_fault_pending[hart]);
        if (bridge.psel[hart] && bridge.penable[hart] && bridge.pready[hart])
          $fwrite(event_fd, "%0d,1,apb_accept,%0d,%0d,%08x,%08x,%0d,%0d\n",
                  cycles, hart, bridge.paddr[hart][4], bridge.paddr[hart],
                  bridge.pwrite[hart] ? bridge.pwdata[hart] : bridge.prdata[hart],
                  bridge.pwrite[hart], bridge.pslverr[hart]);
        if (bridge.enqueue[hart])
          $fwrite(event_fd, "%0d,1,store_enqueue,%0d,%0d,%08x,%08x,%0d,0\n",
                  cycles, hart, bridge.paddr[hart][4], bridge.paddr[hart], bridge.pwdata[hart],
                  bridge.sb_count[hart] + 1'b1);
        if (bridge.enqueue[hart] && bridge.store_complete[hart])
          saw_enqueue_and_drain = 1'b1;
        if (bridge.enqueue[hart] && bridge.store_complete[hart] && bridge.coh_rsp_error[hart])
          saw_enqueue_and_failed_drain = 1'b1;
        if (bridge.store_complete[hart])
          $fwrite(event_fd, "%0d,1,store_drain,%0d,%0d,%08x,%08x,%0d,%0d\n",
                  cycles, hart, bridge.sb_addr[hart][bridge.sb_head[hart]][4],
                  bridge.sb_addr[hart][bridge.sb_head[hart]],
                  bridge.sb_data[hart][bridge.sb_head[hart]], bridge.sb_count[hart],
                  bridge.coh_rsp_error[hart]);
        if (bridge.psel[hart] && bridge.penable[hart] && !bridge.pwrite[hart] &&
            bridge.shared_access[hart] && bridge.forwarded[hart] && bridge.pready[hart])
          $fwrite(event_fd, "%0d,1,load_forward,%0d,%0d,%08x,%08x,%0d,0\n",
                  cycles, hart, bridge.paddr[hart][4], bridge.paddr[hart],
                  bridge.forwarded_data[hart], bridge.sb_count[hart]);
        if (transport.client_req_valid[hart] && transport.client_req_ready[hart])
          $fwrite(event_fd, "%0d,1,fabric_request,%0d,%0d,%08x,%08x,%0d,%0d\n",
                  cycles, hart, transport.client_req_addr[hart][4],
                  transport.client_req_addr[hart], transport.client_req_wdata[hart],
                  transport.client_req_write[hart], sb_occupancy[hart]);
        if (transport.client_rsp_valid[hart] && transport.client_rsp_ready[hart])
          $fwrite(event_fd, "%0d,1,fabric_response,%0d,-1,00000000,%08x,0,%0d\n",
                  cycles, hart, transport.client_rsp_rdata[hart], transport.client_rsp_error[hart]);
      end
      for (int hart = 0; hart < 2; hart++) begin
        if (home_req_valid[hart] && home_req_ready[hart])
          $fwrite(event_fd, "%0d,1,bank_request,%0d,%0d,%08x,%08x,%0d,0\n",
                  cycles, hart, home_req_addr[hart][4], home_req_addr[hart],
                  home_req_wdata[hart], home_req_write[hart]);
      end
      if (transport.tstate[0] != 0 && transport.tstate[1] != 0)
        $fwrite(event_fd, "%0d,1,simultaneous_banks,-1,-1,00000000,00000000,0,0\n", cycles);
    end
  end

  initial begin
    logic error;
    logic [31:0] data, data0, data1;
    int waits;
    test_name = "sb_youngest_forward_h0";
    event_file = "coherent_closure_events.csv";
    void'($value$plusargs("TEST=%s", test_name));
    void'($value$plusargs("EVENT_TRACE_FILE=%s", event_file));
    paddr = '0; pwdata = '0; psel = '0; penable = '0; pwrite = '0;
    hart_qos[0] = 4; hart_qos[1] = 4; backpressure_percent = 0;
    schedule_seed = 32'hc001_cafe; fault_valid = 1'b0; fault_write = 1'b0; fault_addr = '0;
    mem_init_valid = 1'b0; mem_init_addr = '0; mem_init_data = '0;
    cycles = 0; checks = 0; failures = 0; saw_enqueue_and_drain = 1'b0;
    saw_enqueue_and_failed_drain = 1'b0;
    event_fd = $fopen(event_file, "w");
    $fwrite(event_fd, "cycle,epoch,event,hart,bank,address,data,detail0,detail1\n");
    repeat (5) @(posedge clk); rst_n = 1'b1;
    initialize_memory();

    case (test_name)
      "sb_youngest_forward_h0", "sb_youngest_forward_h1": begin
        int hart; hart = test_name == "sb_youngest_forward_h0" ? 0 : 1;
        apb_write(hart, SHARED, 32'h1111_1111, error, waits);
        apb_write(hart, SHARED, 32'h2222_2222, error, waits);
        apb_read(hart, SHARED, data, error, waits);
        check(!error && data == 32'h2222_2222, "youngest matching store forwarded");
      end
      "sb_nonoverlap_bypass_h0", "sb_nonoverlap_bypass_h1": begin
        int hart; hart = test_name == "sb_nonoverlap_bypass_h0" ? 0 : 1;
        apb_write(hart, SHARED, 32'ha5a5_0001, error, waits);
        apb_read(hart, SHARED + 32'h10, data, error, waits);
        check(!error && data == 0 && waits > 0, "non-overlapping load bypassed queued store");
      end
      "sb_full_stall": begin
        apb_write(0, SHARED, 1, error, waits); apb_write(0, SHARED + 4, 2, error, waits);
        apb_write(0, SHARED + 8, 3, error, waits);
        check(!error && waits > 0, "third store stalled behind full FIFO");
      end
      "sb_wrap_h0", "sb_wrap_h1": begin
        int hart; hart = test_name == "sb_wrap_h0" ? 0 : 1;
        for (int n = 0; n < 6; n++) apb_write(hart, SHARED + 4 * (n % 2), 32'h100 + n, error, waits);
        wait_for_fence(hart);
        apb_read(hart, SHARED + 4, data, error, waits);
        check(!error && data == 32'h105, "FIFO head and tail wrapped without reordering");
      end
      "fence_occupancy_two": begin
        apb_write(0, SHARED, 1, error, waits); apb_write(0, SHARED + 4, 2, error, waits);
        check(!fence_done[0] && sb_occupancy[0] == 2, "fence blocked at occupancy two");
        wait_for_fence(0); check(fence_done[0], "fence completed after both drains");
      end
      "store_fault_occupancy_two": begin
        fault_valid = 1'b1; fault_write = 1'b1; fault_addr = 0;
        apb_write(0, SHARED, 32'hf001_f001, error, waits);
        apb_write(0, SHARED + 4, 32'hf002_f002, error, waits);
        while (!store_fault_pending[0]) @(posedge clk);
        repeat (20) @(posedge clk);
        check(sb_occupancy[0] == 2 && stat_drained_stores == 0,
              "failed FIFO head blocked its younger store");
        apb_write(0, MAILBOX + 32'h0e4, 1, error, waits);
        wait_for_fence(0);
      end
      "simultaneous_enqueue_drain": begin
        apb_write(0, SHARED, 32'h1010_1010, error, waits);
        while (!(transport.mstate[0] == 2 && transport.tstate[0] == 3)) @(negedge clk);
        paddr[0] = SHARED + 4; pwdata[0] = 32'h2020_2020; pwrite[0] = 1'b1;
        psel[0] = 1'b1; penable[0] = 1'b0;
        @(negedge clk); penable[0] = 1'b1;
        @(posedge clk); @(negedge clk);
        psel[0] = 1'b0; penable[0] = 1'b0; pwrite[0] = 1'b0;
        wait_for_fence(0);
        check(saw_enqueue_and_drain, "enqueue and successful drain shared one cycle");
      end
      "simultaneous_enqueue_failed_drain": begin
        fault_valid = 1'b1; fault_write = 1'b1; fault_addr = 0;
        apb_write(0, SHARED, 32'hbad0_0001, error, waits);
        while (!(transport.mstate[0] == 2 && transport.tstate[0] == 3)) @(negedge clk);
        paddr[0] = SHARED + 4; pwdata[0] = 32'h600d_0002; pwrite[0] = 1'b1;
        psel[0] = 1'b1; penable[0] = 1'b0;
        @(negedge clk); penable[0] = 1'b1;
        @(posedge clk); @(negedge clk);
        psel[0] = 1'b0; penable[0] = 1'b0; pwrite[0] = 1'b0;
        while (!store_fault_pending[0]) @(posedge clk);
        check(saw_enqueue_and_failed_drain && sb_occupancy[0] == 2 &&
              store_fault_addr[0] == SHARED,
              "failed head and simultaneous enqueue both remained represented");
        fault_valid = 1'b0;
        apb_write(0, MAILBOX + 32'h0e4, 1, error, waits);
        wait_for_fence(0);
        apb_read(0, SHARED, data0, error, waits);
        apb_read(0, SHARED + 4, data1, error, waits);
        check(!error && data0 == 32'hbad0_0001 && data1 == 32'h600d_0002,
              "explicit retry drained retained head before younger store");
      end
      "store_fault_other_bank_progress": begin
        fault_valid = 1'b1; fault_write = 1'b1; fault_addr = 0;
        paired_write(SHARED, 32'hf00d_0000, SHARED + 32'h10, 32'h600d_0010);
        while (!store_fault_pending[0]) @(posedge clk);
        wait_for_fence(1);
        apb_read(1, SHARED + 32'h10, data1, error, waits);
        check(!error && data1 == 32'h600d_0010 && sb_occupancy[0] != 0 &&
              stat_simultaneous_bank_cycles > 0,
              "bank 1 completed while bank 0 retained a failed store");
        fault_valid = 1'b0;
        apb_write(0, MAILBOX + 32'h0e4, 1, error, waits);
        wait_for_fence(0);
      end
      "mailbox_unfenced_overtake": begin
        apb_write(0, SHARED, 32'h55aa, error, waits);
        apb_write(0, MAILBOX, 1, error, waits);
        check(sb_occupancy[0] != 0, "unfenced uncached write overtook buffered store");
      end
      "mailbox_fenced_order": begin
        apb_write(0, SHARED, 32'h55aa, error, waits); wait_for_fence(0);
        apb_write(0, MAILBOX, 1, error, waits);
        check(sb_occupancy[0] == 0, "fenced uncached write followed drained store");
      end
      "clean_conflict_h0", "clean_conflict_h1": begin
        int hart; hart = test_name == "clean_conflict_h0" ? 0 : 1;
        apb_read(hart, SHARED, data, error, waits);
        apb_read(hart, SHARED + 32'h80, data, error, waits);
        check(!error && stat_dirty_writebacks == 0, "clean conflict caused no writeback");
      end
      "dirty_conflict_h0", "dirty_conflict_h1": begin
        int hart; hart = test_name == "dirty_conflict_h0" ? 0 : 1;
        apb_write(hart, SHARED, 32'hdead_0000 + hart, error, waits); wait_for_fence(hart);
        apb_read(hart, SHARED + 32'h80, data, error, waits);
        check(!error && stat_dirty_writebacks > 0, "dirty victim committed before replacement");
      end
      "shared_upgrade_h0", "shared_upgrade_h1": begin
        int owner, other; owner = test_name == "shared_upgrade_h0" ? 0 : 1; other = 1 - owner;
        apb_read(owner, SHARED, data, error, waits); apb_read(other, SHARED, data, error, waits);
        apb_write(owner, SHARED, 32'hacce_0000 + owner, error, waits); wait_for_fence(owner);
        apb_read(other, SHARED, data, error, waits);
        check(!error && data == 32'hacce_0000 + owner && stat_invalidations > 0,
              "shared line upgraded and remote copy invalidated");
      end
      "dirty_intervention_h0_h1", "dirty_intervention_h1_h0": begin
        int owner, other; owner = test_name == "dirty_intervention_h0_h1" ? 0 : 1; other = 1 - owner;
        apb_write(owner, SHARED, 32'h1a2b_0000 + owner, error, waits); wait_for_fence(owner);
        apb_read(other, SHARED, data, error, waits);
        check(!error && data == 32'h1a2b_0000 + owner && stat_interventions > 0,
              "modified owner supplied intervention data");
      end
      "same_line_read_write": begin
        fork
          apb_write(0, SHARED, 32'habcd_1234, error, waits);
          apb_read(1, SHARED, data1, error, waits);
        join
        wait_for_fence(0); apb_read(1, SHARED, data1, error, waits);
        check(!error && data1 == 32'habcd_1234, "same-line read/write converged");
      end
      "same_line_write_write": begin
        paired_write(SHARED, 32'h1111_aaaa, SHARED, 32'h2222_bbbb);
        wait_for_both_fences();
        apb_read(0, SHARED, data0, error, waits); apb_read(1, SHARED, data1, error, waits);
        check(data0 == data1 && (data0 == 32'h1111_aaaa || data0 == 32'h2222_bbbb),
              "same-line writers converged to one coherent value");
      end
      "dual_bank_overlap_end_to_end": begin
        paired_write(SHARED, 32'h0101_0101, SHARED + 32'h10, 32'h0202_0202);
        wait_for_both_fences();
        check(stat_simultaneous_bank_cycles > 0, "different banks progressed concurrently");
      end
      default: $fatal(1, "unknown closure test %s", test_name);
    endcase

    wait_for_both_fences(); repeat (20) @(posedge clk);
    dump_final_state(); $fclose(event_fd);
    $display("CLOSURE_SUMMARY|test=%s|status=%s|checks=%0d|failures=%0d|cycles=%0d|forwarded=%0d|bypassed=%0d|drained=%0d|invalidations=%0d|interventions=%0d|writebacks=%0d|simultaneous=%0d",
             test_name, failures == 0 ? "PASS" : "FAIL", checks, failures, cycles,
             stat_forwarded_loads, stat_bypassed_loads, stat_drained_stores,
             stat_invalidations, stat_interventions, stat_dirty_writebacks,
             stat_simultaneous_bank_cycles);
    if (failures != 0) $fatal(1, "closure scenario failed");
    $finish;
  end

  a_no_unknown_response: assert property (@(posedge clk) disable iff (!rst_n)
    |coh_rsp_valid |-> !$isunknown({coh_rsp_error, coh_rsp_rdata}));
  a_fence_exact_quiescence: assert property (@(posedge clk) disable iff (!rst_n)
    fence_done[0] |-> sb_occupancy[0] == 0);
  a_fence_exact_quiescence_h1: assert property (@(posedge clk) disable iff (!rst_n)
    fence_done[1] |-> sb_occupancy[1] == 0);
endmodule
