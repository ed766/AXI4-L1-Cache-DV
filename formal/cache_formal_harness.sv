module cache_formal_harness;
  (* gclk *) logic clk;
  logic rst_n = 0;
  always_ff @(posedge clk) rst_n <= 1;

  (* anyseq *) logic cpu_req_valid;
  (* anyseq *) logic [31:0] cpu_req_addr;
  (* anyseq *) logic cpu_req_write;
  (* anyseq *) logic [31:0] cpu_req_wdata;
  (* anyseq *) logic [3:0] cpu_req_wstrb;
  (* anyseq *) logic [2:0] cpu_req_size;
  (* anyseq *) logic [7:0] cpu_req_id;
  (* anyseq *) logic cpu_rsp_ready;
  logic cpu_req_ready, cpu_rsp_valid, cpu_rsp_error;
  logic [31:0] cpu_rsp_rdata;
  logic [7:0] cpu_rsp_id;

  logic [31:0] awaddr, araddr;
  logic [7:0] awlen, arlen;
  logic [2:0] awsize, arsize;
  logic [1:0] awburst, arburst;
  logic awvalid, wvalid, wlast, bready, arvalid, rready;
  logic [63:0] wdata;
  logic [7:0] wstrb;
  logic [4:0] mon_state;
  logic mon_hit, mon_miss, mon_evict;
  logic [1:0] mon_refill_beat, mon_writeback_beat;
  logic maint_ready, maint_busy, maint_done, maint_error;

  logic bvalid;
  logic rvalid;
  logic [1:0] read_beat;
  always_ff @(posedge clk) begin
    if (!rst_n) begin bvalid <= 0; rvalid <= 0; read_beat <= 0; end
    else begin
      if (wvalid && wlast) bvalid <= 1;
      if (bvalid && bready) bvalid <= 0;
      if (arvalid) begin rvalid <= 1; read_beat <= 0; end
      else if (rvalid && rready) begin
        if (read_beat == 3) rvalid <= 0;
        else read_beat <= read_beat + 1;
      end
    end
  end

  l1_dcache_top #(.SETS(4)) dut (
    .clk, .rst_n,
    .cpu_req_valid, .cpu_req_ready, .cpu_req_addr, .cpu_req_write,
    .cpu_req_wdata, .cpu_req_wstrb, .cpu_req_size, .cpu_req_id,
    .cpu_rsp_valid, .cpu_rsp_ready, .cpu_rsp_rdata, .cpu_rsp_id, .cpu_rsp_error,
    .maint_valid(1'b0), .maint_ready, .maint_cmd(2'b0),
    .maint_busy, .maint_done, .maint_error,
    .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
    .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(1'b1),
    .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
    .m_axi_wvalid(wvalid), .m_axi_wready(1'b1),
    .m_axi_bresp(2'b0), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
    .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
    .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(1'b1),
    .m_axi_rdata(64'h55aa_55aa_a55a_a55a), .m_axi_rresp(2'b0),
    .m_axi_rlast(read_beat == 3), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
    .mon_state, .mon_hit, .mon_miss, .mon_evict,
    .mon_refill_beat, .mon_writeback_beat
  );

  logic [9:0] accepted, responded;
  always_ff @(posedge clk) begin
    if (!rst_n) begin accepted <= 0; responded <= 0; end
    else begin
      if (cpu_req_valid && cpu_req_ready) accepted <= accepted + 1;
      if (cpu_rsp_valid && cpu_rsp_ready) responded <= responded + 1;
      assert(responded <= accepted);
      assert(!(awvalid && arvalid));
      if (wvalid) assert(awlen == 3);
      cover(mon_miss && rvalid && read_beat == 3);
      cover(mon_evict);
    end
  end
endmodule
