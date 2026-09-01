module coherent_impl_properties;
  (* gclk *) logic clk;
  logic reset_q = 1'b1;
  always_ff @(posedge clk) reset_q <= 1'b0;
  wire rst_n = !reset_q;

`ifdef FORMAL_IMPL_MSI
  (* anyseq *) logic [1:0] req_valid, req_write;
  (* anyseq *) logic [1:0][31:0] req_addr, req_wdata;
  logic [1:0] req_ready, rsp_valid;
  logic [1:0][31:0] rsp_rdata;
  logic [31:0] read_miss, write_miss, invalidations, interventions, writebacks;
  logic [1:0][1:0][1:0] formal_line_state;
  logic [1:0][1:0][27:0] formal_line_tag;
  logic [1:0] formal_ctrl_state;
  logic formal_dirty_victim;

  msi_two_cache_subsystem #(.LINES(2), .WORDS_PER_LINE(2), .MEM_WORDS(16)) dut (
    .clk, .rst_n,
    .c0_req_valid(req_valid[0]), .c0_req_ready(req_ready[0]),
    .c0_req_write(req_write[0]), .c0_req_addr(req_addr[0]), .c0_req_wdata(req_wdata[0]),
    .c0_rsp_valid(rsp_valid[0]), .c0_rsp_ready(1'b1), .c0_rsp_rdata(rsp_rdata[0]),
    .c1_req_valid(req_valid[1]), .c1_req_ready(req_ready[1]),
    .c1_req_write(req_write[1]), .c1_req_addr(req_addr[1]), .c1_req_wdata(req_wdata[1]),
    .c1_rsp_valid(rsp_valid[1]), .c1_rsp_ready(1'b1), .c1_rsp_rdata(rsp_rdata[1]),
    .mem_init_valid(1'b0), .mem_init_addr('0), .mem_init_data('0),
    .stat_read_miss(read_miss), .stat_write_miss(write_miss),
    .stat_invalidations(invalidations), .stat_interventions(interventions),
    .stat_dirty_writebacks(writebacks), .formal_line_state, .formal_line_tag,
    .formal_ctrl_state, .formal_dirty_victim
  );

  always_ff @(posedge clk) if (rst_n) begin
    assume (req_addr[0][31:5] == 0 && req_addr[1][31:5] == 0);
    assume (req_addr[0][1:0] == 0 && req_addr[1][1:0] == 0);
`ifdef PROP_NO_DUAL_MODIFIED
    assert (!(formal_line_state[0][0] == 2'b10 && formal_line_state[1][0] == 2'b10 &&
              formal_line_tag[0][0] == formal_line_tag[1][0]));
    assert (!(formal_line_state[0][1] == 2'b10 && formal_line_state[1][1] == 2'b10 &&
              formal_line_tag[0][1] == formal_line_tag[1][1]));
    cover (formal_line_state[0][0] == 2'b10);
`endif
`ifdef PROP_NO_SHARED_MODIFIED
    assert (!(((formal_line_state[0][0] == 2'b10 && formal_line_state[1][0] == 2'b01) ||
               (formal_line_state[1][0] == 2'b10 && formal_line_state[0][0] == 2'b01)) &&
              formal_line_tag[0][0] == formal_line_tag[1][0]));
    assert (!(((formal_line_state[0][1] == 2'b10 && formal_line_state[1][1] == 2'b01) ||
               (formal_line_state[1][1] == 2'b10 && formal_line_state[0][1] == 2'b01)) &&
              formal_line_tag[0][1] == formal_line_tag[1][1]));
    cover (formal_line_state[0][0] == 2'b01 && formal_line_state[1][0] == 2'b01);
`endif
`ifdef PROP_DIRTY_VICTIM_WB
    if ($past(rst_n && formal_dirty_victim))
      assert (writebacks == $past(writebacks) + 1'b1);
    cover (formal_dirty_victim);
`endif
  end
`else
  (* anyseq *) logic [1:0][31:0] paddr, pwdata;
  (* anyseq *) logic [1:0] psel, penable, pwrite;
  logic [1:0][31:0] prdata, coh_req_addr, coh_req_wdata, coh_rsp_rdata;
  logic [1:0] pready, pslverr, coh_req_valid, coh_req_write, coh_rsp_ready;
  logic [1:0] fence_done, firmware_done, store_fault_pending;
  logic [1:0][1:0] occupancy;
  logic [1:0][31:0] result_code, observed, fault_addr;
  logic [31:0] forwarded, bypassed, drained;
  logic [1:0] response_pending;
  (* anyseq *) logic [1:0] response_error;
  logic [1:0][1:0] formal_sb_count;
  logic [1:0] formal_forwarded, formal_port_busy, formal_port_is_load, formal_req_pending;
  logic [1:0][31:0] formal_forwarded_data, formal_head_addr, formal_head_data;

  dual_hart_apb_store_buffer #(.STORE_DRAIN_DELAY(1)) dut (
    .clk, .rst_n, .paddr, .psel, .penable, .pwrite, .pwdata, .prdata, .pready, .pslverr,
    .coh_req_valid, .coh_req_ready({2{1'b1}}), .coh_req_write, .coh_req_addr,
    .coh_req_wdata, .coh_rsp_valid(response_pending), .coh_rsp_ready,
    .coh_rsp_rdata, .coh_rsp_error(response_error), .fence_done, .sb_occupancy(occupancy),
    .result_code, .firmware_done, .observed_value(observed),
    .store_fault_pending, .store_fault_addr(fault_addr),
    .stat_forwarded_loads(forwarded), .stat_bypassed_loads(bypassed),
    .stat_drained_stores(drained), .formal_sb_count, .formal_forwarded,
    .formal_forwarded_data, .formal_head_addr, .formal_head_data, .formal_port_busy,
    .formal_port_is_load,
    .formal_req_pending
  );
  always_comb coh_rsp_rdata = coh_req_addr;
  always_ff @(posedge clk) begin
    if (!rst_n) response_pending <= '0;
    else response_pending <= coh_req_valid;
  end
  always_ff @(posedge clk) if (rst_n) begin
    assume ((penable & ~psel) == 0);
    if ($past(rst_n)) begin
      for (int apb_hart = 0; apb_hart < 2; apb_hart++) begin
        if ($past(psel[apb_hart] && penable[apb_hart] && pready[apb_hart]))
          assume (!penable[apb_hart]);
        if ($past(psel[apb_hart] && penable[apb_hart] && !pready[apb_hart])) begin
          assume (psel[apb_hart] && penable[apb_hart]);
          assume (paddr[apb_hart] == $past(paddr[apb_hart]));
          assume (pwrite[apb_hart] == $past(pwrite[apb_hart]));
          assume (pwdata[apb_hart] == $past(pwdata[apb_hart]));
        end
      end
    end
    assume (!psel[0] || paddr[0][1:0] == 0);
    assume (!psel[1] || paddr[1][1:0] == 0);
    assert (formal_sb_count[0] <= 2);
    assert (formal_sb_count[1] <= 2);
`ifdef PROP_FIFO_ORDER
    assert (occupancy[0] == formal_sb_count[0]);
    assert (occupancy[1] == formal_sb_count[1]);
    cover (occupancy[0] == 2 || occupancy[1] == 2);
`endif
`ifdef PROP_FORWARDING
    if (formal_forwarded[0] && formal_sb_count[0] == 1)
      assert (formal_forwarded_data[0] == formal_head_data[0]);
    if (formal_forwarded[1] && formal_sb_count[1] == 1)
      assert (formal_forwarded_data[1] == formal_head_data[1]);
    cover (formal_forwarded[0] || formal_forwarded[1]);
`endif
`ifdef PROP_FENCE
    assert (fence_done[0] == (formal_sb_count[0] == 0 && !formal_port_busy[0] && !formal_req_pending[0]));
    assert (fence_done[1] == (formal_sb_count[1] == 0 && !formal_port_busy[1] && !formal_req_pending[1]));
    cover ((!fence_done[0] && formal_sb_count[0] != 0) ||
           (!fence_done[1] && formal_sb_count[1] != 0));
`endif
`ifdef PROP_FAILED_HEAD
    if (store_fault_pending[0]) begin
      assert (formal_sb_count[0] != 0);
      assert (formal_head_addr[0] == fault_addr[0]);
    end
    if (store_fault_pending[1]) begin
      assert (formal_sb_count[1] != 0);
      assert (formal_head_addr[1] == fault_addr[1]);
    end
    cover (store_fault_pending[0] || store_fault_pending[1]);
`endif
  end
`endif
endmodule
