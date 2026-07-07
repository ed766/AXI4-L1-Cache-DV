module cache_formal_harness;
  (* gclk *) logic clk;
  (* anyseq *) logic rst_n;
  logic f_past_valid = 0;
  always_ff @(posedge clk) begin
    f_past_valid <= 1;
    if (!f_past_valid) assume(!rst_n);
    else assume(rst_n);
  end

  (* anyseq *) logic cpu_req_valid;
  (* anyseq *) logic [31:0] cpu_req_addr;
  (* anyseq *) logic cpu_req_write;
  (* anyseq *) logic [31:0] cpu_req_wdata;
  (* anyseq *) logic [3:0] cpu_req_wstrb;
  (* anyseq *) logic [7:0] cpu_req_id;
  (* anyseq *) logic cpu_rsp_ready;
  (* anyseq *) logic maint_valid;
  (* anyseq *) logic [1:0] maint_cmd;
  (* anyseq *) logic [1:0] symbolic_rresp;
  (* anyseq *) logic [1:0] symbolic_bresp;

  logic cpu_req_ready, cpu_rsp_valid, cpu_rsp_error;
  logic [31:0] cpu_rsp_rdata;
  logic [7:0] cpu_rsp_id;
  logic maint_ready, maint_busy, maint_done, maint_error;
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

  logic bvalid, rvalid;
  logic [1:0] bresp, rresp;
  logic [63:0] rdata;
  logic rlast;
  logic [1:0] read_beat;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      bvalid <= 0;
      bresp <= 0;
      rvalid <= 0;
      rresp <= 0;
      rdata <= 0;
      rlast <= 0;
      read_beat <= 0;
    end else begin
      if (wvalid && wlast) begin
        bvalid <= 1;
        bresp <= symbolic_bresp;
      end else if (bvalid && bready) begin
        bvalid <= 0;
      end

      if (arvalid) begin
        rvalid <= 1;
        read_beat <= 0;
        rdata <= 64'h55aa_55aa_a55a_a55a;
        rresp <= symbolic_rresp;
        rlast <= 0;
      end else if (rvalid && rready) begin
        if (read_beat == 3) begin
          rvalid <= 0;
          rlast <= 0;
        end else begin
          read_beat <= read_beat + 1;
          rdata <= 64'h55aa_55aa_a55a_a55a;
          rresp <= symbolic_rresp;
          rlast <= read_beat == 2;
        end
      end
    end
  end

  l1_dcache_top #(.SETS(2), .WAYS(2)) dut (
    .clk, .rst_n,
    .cpu_req_valid, .cpu_req_ready, .cpu_req_addr, .cpu_req_write,
    .cpu_req_wdata, .cpu_req_wstrb, .cpu_req_size(3'd2), .cpu_req_id,
    .cpu_rsp_valid, .cpu_rsp_ready, .cpu_rsp_rdata, .cpu_rsp_id, .cpu_rsp_error,
    .maint_valid, .maint_ready, .maint_cmd, .maint_busy, .maint_done, .maint_error,
    .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
    .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(1'b1),
    .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
    .m_axi_wvalid(wvalid), .m_axi_wready(1'b1),
    .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
    .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
    .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(1'b1),
    .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
    .m_axi_rvalid(rvalid), .m_axi_rready(rready),
    .mon_state, .mon_hit, .mon_miss, .mon_evict,
    .mon_refill_beat, .mon_writeback_beat
  );

  logic [7:0] accepted_count, response_count;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      accepted_count <= 0;
      response_count <= 0;
    end else begin
      if ($past(rst_n) && $past(cpu_req_valid && !cpu_req_ready))
        assume({cpu_req_addr, cpu_req_write, cpu_req_wdata, cpu_req_wstrb, cpu_req_id} ==
               $past({cpu_req_addr, cpu_req_write, cpu_req_wdata, cpu_req_wstrb, cpu_req_id}));
      assume(maint_cmd <= 2);
      assume(symbolic_rresp <= 2);
      assume(symbolic_bresp <= 2);
      assume(cpu_req_addr[31:8] == 0);
      assume(cpu_req_wdata == 0);
      assume(cpu_req_wstrb == 4'hf);
      assume(cpu_rsp_ready);

      if (cpu_req_valid && cpu_req_ready) begin
        accepted_count <= accepted_count + 1;
      end
      if (cpu_rsp_valid && cpu_rsp_ready) begin
        response_count <= response_count + 1;
      end
      assert(response_count <= accepted_count);

      if (rvalid) assume(rlast == (read_beat == 3));
    end
  end
endmodule
