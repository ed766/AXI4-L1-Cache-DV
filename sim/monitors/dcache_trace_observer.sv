`timescale 1ns/1ps

module dcache_trace_observer #(
  parameter int INDEX_BITS = 6,
  parameter int TAG_BITS = 21
) (
  input logic clk,
  input logic rst_n,
  input logic [4:0] state,
  input logic cpu_req_valid,
  input logic cpu_req_ready,
  input logic [31:0] cpu_req_addr,
  input logic cpu_req_write,
  input logic [31:0] cpu_req_wdata,
  input logic [3:0] cpu_req_wstrb,
  input logic [2:0] cpu_req_size,
  input logic [7:0] cpu_req_id,
  input logic cpu_rsp_valid,
  input logic cpu_rsp_ready,
  input logic [31:0] cpu_rsp_rdata,
  input logic [7:0] cpu_rsp_id,
  input logic cpu_rsp_error,
  input logic maint_valid,
  input logic maint_ready,
  input logic [1:0] maint_cmd,
  input logic maint_done,
  input logic maint_error,
  input logic [1:0] maint_cmd_q,
  input logic [INDEX_BITS-1:0] maint_set,
  input logic maint_way,
  input logic maint_line_valid,
  input logic maint_line_dirty,
  input logic [31:0] req_addr_q,
  input logic req_write_q,
  input logic [3:0] req_wstrb_q,
  input logic [7:0] req_id_q,
  input logic hit,
  input logic hit_way,
  input logic lookup_victim_way,
  input logic lookup_victim_valid,
  input logic lookup_victim_dirty,
  input logic lookup_lru,
  input logic victim_way,
  input logic [INDEX_BITS-1:0] victim_set,
  input logic active_victim_valid,
  input logic active_victim_dirty,
  input logic [TAG_BITS-1:0] active_victim_tag,
  input logic refill_error,
  input logic [1:0] wb_beat,
  input logic [1:0] refill_beat,
  input logic [31:0] m_axi_awaddr,
  input logic m_axi_awvalid,
  input logic m_axi_awready,
  input logic [63:0] m_axi_wdata,
  input logic [7:0] m_axi_wstrb,
  input logic m_axi_wlast,
  input logic m_axi_wvalid,
  input logic m_axi_wready,
  input logic [1:0] m_axi_bresp,
  input logic m_axi_bvalid,
  input logic m_axi_bready,
  input logic [31:0] m_axi_araddr,
  input logic m_axi_arvalid,
  input logic m_axi_arready,
  input logic [63:0] m_axi_rdata,
  input logic [1:0] m_axi_rresp,
  input logic m_axi_rlast,
  input logic m_axi_rvalid,
  input logic m_axi_rready
);
  import dcache_pkg::ST_LOOKUP;
  import dcache_pkg::ST_REFILL_FINISH;
  import dcache_pkg::ST_MAINT_SCAN;
  integer trace_fd;
  integer cycle;
  integer epoch;
  integer bp_pct;
  string trace_file;
  logic prior_rst_n;
  logic trace_flush;

`define TRACE_EMIT(event_name, id, addr, write_value, data, strobe, size_value, error_value, hit_value, way_value, valid_value, dirty_value, lru_value, beat_value, resp_value, maint_value) \
  if (trace_fd != 0) begin \
    $fwrite(trace_fd, "%0d,%0d,%s,%0d,%08x,%0d,%016x,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n", \
            cycle, epoch, event_name, id, addr, write_value, data, strobe, \
            size_value, error_value, hit_value, way_value, valid_value, \
            dirty_value, lru_value, beat_value, resp_value, maint_value, bp_pct, state); \
    if (trace_flush) $fflush(trace_fd); \
  end

  task automatic emit_final_memory(
    input logic [31:0] byte_addr,
    input logic [31:0] value
  );
    `TRACE_EMIT("FINAL_MEMORY", -1, byte_addr, 0, value, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0);
  endtask

  initial begin
    trace_fd = 0;
    cycle = 0;
    epoch = 0;
    bp_pct = 0;
    prior_rst_n = 0;
    trace_flush = $test$plusargs("TRACE_FLUSH");
    void'($value$plusargs("BP_PCT=%d", bp_pct));
    if ($value$plusargs("TRACE_FILE=%s", trace_file)) begin
      trace_fd = $fopen(trace_file, "w");
      if (trace_fd == 0) $fatal(1, "Unable to open trace file %s", trace_file);
      $fwrite(trace_fd, "cycle,epoch,event,id,addr,write,data,wstrb,size,error,hit,way,valid,dirty,lru,beat,resp,maint_cmd,bp_pct,state\n");
    end
  end

  always_ff @(posedge clk) begin
    cycle <= cycle + 1;
    prior_rst_n <= rst_n;
    if (!prior_rst_n && rst_n) begin
      epoch <= epoch + 1;
      `TRACE_EMIT("RESET_RELEASE", -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    end
    if (prior_rst_n && !rst_n)
      `TRACE_EMIT("RESET_ASSERT", -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    if (rst_n) begin
      if (cpu_req_valid && cpu_req_ready)
        `TRACE_EMIT("CPU_ACCEPT", cpu_req_id, cpu_req_addr, cpu_req_write, cpu_req_wdata,
             cpu_req_wstrb, cpu_req_size, 0, 0, 0, 0, 0, 0, 0, 0, 0);
      if (state == ST_LOOKUP)
        `TRACE_EMIT("LOOKUP", req_id_q, req_addr_q, req_write_q, 0, req_wstrb_q, 0, 0,
             hit, hit ? hit_way : lookup_victim_way,
             hit ? 1 : lookup_victim_valid,
             hit ? 0 : lookup_victim_dirty, lookup_lru, 0, 0, 0);
      if (cpu_rsp_valid && cpu_rsp_ready)
        `TRACE_EMIT("CPU_RESPONSE", cpu_rsp_id, 0, 0, cpu_rsp_rdata, 0, 0,
             cpu_rsp_error, 0, 0, 0, 0, 0, 0, 0, 0);
      if (m_axi_awvalid && m_axi_awready)
        `TRACE_EMIT("AXI_AW", req_id_q, m_axi_awaddr, 1, 0, 0, 0, 0, 0,
             victim_way, active_victim_valid, active_victim_dirty, 0, 0, 0, maint_cmd_q);
      if (m_axi_wvalid && m_axi_wready)
        `TRACE_EMIT("AXI_W", req_id_q, m_axi_awaddr, 1, m_axi_wdata, m_axi_wstrb, 0, 0,
             0, victim_way, active_victim_valid, active_victim_dirty, 0,
             wb_beat, m_axi_wlast, 0);
      if (m_axi_bvalid && m_axi_bready)
        `TRACE_EMIT("AXI_B", req_id_q, m_axi_awaddr, 1, 0, 0, 0,
             m_axi_bresp != 0, 0, victim_way, active_victim_valid,
             active_victim_dirty, 0, wb_beat, m_axi_bresp, maint_cmd_q);
      if (m_axi_arvalid && m_axi_arready)
        `TRACE_EMIT("AXI_AR", req_id_q, m_axi_araddr, 0, 0, 0, 0, 0, 0,
             victim_way, active_victim_valid, active_victim_dirty, 0, 0, 0, 0);
      if (m_axi_rvalid && m_axi_rready)
        `TRACE_EMIT("AXI_R", req_id_q, m_axi_araddr, 0, m_axi_rdata, 0, 0,
             m_axi_rresp != 0, 0, victim_way, active_victim_valid,
             active_victim_dirty, 0, refill_beat, m_axi_rresp, 0);
      if (state == ST_REFILL_FINISH && !refill_error)
        `TRACE_EMIT("LINE_INSTALL", req_id_q, req_addr_q, req_write_q, 0, req_wstrb_q,
             0, 0, 0, victim_way, active_victim_valid, active_victim_dirty,
             0, 0, 0, 0);
      if (maint_valid && maint_ready)
        `TRACE_EMIT("MAINT_ACCEPT", -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, maint_cmd);
      if (state == ST_MAINT_SCAN)
        `TRACE_EMIT("MAINT_SCAN", -1, {{(32-INDEX_BITS){1'b0}}, maint_set}, 0, 0, 0, 0,
             0, 0, maint_way, maint_line_valid, maint_line_dirty, 0, 0, 0, maint_cmd_q);
      if (maint_done)
        `TRACE_EMIT("MAINT_DONE", -1, 0, 0, 0, 0, 0, maint_error, 0, 0, 0, 0, 0, 0, 0, maint_cmd_q);
    end
  end

  final if (trace_fd != 0) $fclose(trace_fd);
`undef TRACE_EMIT
endmodule

bind l1_dcache_top dcache_trace_observer #(
  .INDEX_BITS(INDEX_BITS), .TAG_BITS(TAG_BITS)
) u_trace_observer (
  .clk, .rst_n, .state, .cpu_req_valid, .cpu_req_ready, .cpu_req_addr,
  .cpu_req_write, .cpu_req_wdata, .cpu_req_wstrb, .cpu_req_size, .cpu_req_id,
  .cpu_rsp_valid, .cpu_rsp_ready, .cpu_rsp_rdata, .cpu_rsp_id, .cpu_rsp_error,
  .maint_valid, .maint_ready, .maint_cmd, .maint_done, .maint_error,
  .maint_cmd_q, .maint_set, .maint_way, .maint_line_valid, .maint_line_dirty,
  .req_addr_q, .req_write_q, .req_wstrb_q, .req_id_q, .hit, .hit_way,
  .lookup_victim_way, .lookup_victim_valid, .lookup_victim_dirty, .lookup_lru,
  .victim_way, .victim_set, .active_victim_valid, .active_victim_dirty,
  .active_victim_tag, .refill_error, .wb_beat, .refill_beat,
  .m_axi_awaddr, .m_axi_awvalid, .m_axi_awready, .m_axi_wdata, .m_axi_wstrb,
  .m_axi_wlast, .m_axi_wvalid, .m_axi_wready, .m_axi_bresp, .m_axi_bvalid,
  .m_axi_bready, .m_axi_araddr, .m_axi_arvalid, .m_axi_arready, .m_axi_rdata,
  .m_axi_rresp, .m_axi_rlast, .m_axi_rvalid, .m_axi_rready
);
