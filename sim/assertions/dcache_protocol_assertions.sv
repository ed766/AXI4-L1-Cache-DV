`timescale 1ns/1ps
module dcache_protocol_assertions #(
  parameter int TAG_BITS = 21,
  parameter int WAYS = 2
) (
  input logic clk,
  input logic rst_n,
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
  input logic m_axi_awvalid,
  input logic m_axi_awready,
  input logic [31:0] m_axi_awaddr,
  input logic [7:0] m_axi_awlen,
  input logic [2:0] m_axi_awsize,
  input logic [1:0] m_axi_awburst,
  input logic m_axi_wvalid,
  input logic m_axi_wready,
  input logic [63:0] m_axi_wdata,
  input logic [7:0] m_axi_wstrb,
  input logic m_axi_wlast,
  input logic [1:0] m_axi_bresp,
  input logic m_axi_bvalid,
  input logic m_axi_bready,
  input logic m_axi_arvalid,
  input logic m_axi_arready,
  input logic [31:0] m_axi_araddr,
  input logic [7:0] m_axi_arlen,
  input logic [2:0] m_axi_arsize,
  input logic [1:0] m_axi_arburst,
  input logic m_axi_rvalid,
  input logic m_axi_rready,
  input logic [63:0] m_axi_rdata,
  input logic [1:0] m_axi_rresp,
  input logic m_axi_rlast,
  input logic [4:0] state,
  input logic hit,
  input logic lookup_victim_way,
  input logic lookup_victim_valid,
  input logic lookup_victim_dirty,
  input logic lookup_way0_valid,
  input logic lookup_way1_valid,
  input logic active_victim_valid,
  input logic active_victim_dirty,
  input logic [TAG_BITS-1:0] active_victim_tag,
  input logic refill_error,
  input logic [1:0] wb_beat,
  input logic [1:0] refill_beat,
  input logic maint_valid,
  input logic maint_busy
);
  import dcache_pkg::ST_LOOKUP;
  import dcache_pkg::ST_WB_AW;
  import dcache_pkg::ST_WB_B;
  import dcache_pkg::ST_REFILL_AR;
  import dcache_pkg::ST_REFILL_FINISH;
  int unsigned accepted_count;
  int unsigned response_count;
  logic request_pending;
  logic [7:0] pending_id;
  logic refill_snapshot_valid;
  logic refill_snapshot_dirty;
  logic [TAG_BITS-1:0] refill_snapshot_tag;
  logic dirty_writeback_pending;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      accepted_count <= 0;
      response_count <= 0;
      request_pending <= 0;
      pending_id <= 0;
      refill_snapshot_valid <= 0;
      refill_snapshot_dirty <= 0;
      refill_snapshot_tag <= 0;
      dirty_writeback_pending <= 0;
    end else begin
      if (cpu_req_valid && cpu_req_ready) begin
        accepted_count <= accepted_count + 1;
        a_no_second_accept_while_pending: assert (!request_pending)
          else $error("Accepted a second request while one was pending");
        request_pending <= 1;
        pending_id <= cpu_req_id;
      end
      if (cpu_rsp_valid && cpu_rsp_ready) begin
        response_count <= response_count + 1;
        a_single_matching_response_per_accept: assert (request_pending && cpu_rsp_id == pending_id)
          else $error("Response was duplicated, orphaned, or carried the wrong ID");
        request_pending <= 0;
      end
      if (state == ST_REFILL_AR && m_axi_arvalid && m_axi_arready) begin
        refill_snapshot_valid <= active_victim_valid;
        refill_snapshot_dirty <= active_victim_dirty;
        refill_snapshot_tag <= active_victim_tag;
      end
      if (state == ST_LOOKUP && !hit && lookup_victim_valid && lookup_victim_dirty)
        dirty_writeback_pending <= 1;
      if (state == ST_WB_B && m_axi_bvalid && m_axi_bready)
        dirty_writeback_pending <= 0;
      a_no_refill_before_writeback_complete: assert (!(m_axi_arvalid && dirty_writeback_pending))
        else $error("Refill started before dirty-victim writeback completed");
      if (state == ST_REFILL_FINISH && refill_error)
        a_failed_refill_no_install: assert (
          active_victim_valid == refill_snapshot_valid &&
          active_victim_dirty == refill_snapshot_dirty &&
          active_victim_tag == refill_snapshot_tag)
          else $error("Failed refill changed victim line state");
      a_response_not_ahead: assert (response_count <= accepted_count)
        else $error("CPU response count exceeded accepted request count");
    end
  end

  a_rsp_stable: assert property (@(posedge clk) disable iff (!rst_n)
    cpu_rsp_valid && !cpu_rsp_ready |=>
      $stable({cpu_rsp_rdata, cpu_rsp_id, cpu_rsp_error}));
  a_aw_stable: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_awvalid && !m_axi_awready
      |=> $stable({m_axi_awaddr, m_axi_awlen, m_axi_awsize, m_axi_awburst}));
  a_w_stable: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_wvalid && !m_axi_wready |=> $stable({m_axi_wdata, m_axi_wstrb, m_axi_wlast}));
  a_ar_stable: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_arvalid && !m_axi_arready
      |=> $stable({m_axi_araddr, m_axi_arlen, m_axi_arsize, m_axi_arburst}));
  a_r_stable: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_rvalid && !m_axi_rready |=> $stable({m_axi_rdata, m_axi_rresp, m_axi_rlast}));

  a_failed_writeback_preserves_dirty: assert property (@(posedge clk) disable iff (!rst_n)
    state == ST_WB_B && m_axi_bvalid && m_axi_bready && m_axi_bresp != 0
      |=> active_victim_dirty);
  a_dirty_victim_writeback_before_refill: assert property (@(posedge clk) disable iff (!rst_n)
    state == ST_LOOKUP && !hit && lookup_victim_valid && lookup_victim_dirty
      |=> state == ST_WB_AW);
  a_wlast_exactly_final_beat: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_wvalid |-> (m_axi_wlast == (wb_beat == 2'd3)));
  a_rlast_exactly_final_beat: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_rvalid |-> (m_axi_rlast == (refill_beat == 2'd3)));
  a_invalid_way_precedes_lru: assert property (@(posedge clk) disable iff (!rst_n)
    state == ST_LOOKUP && !hit && (!lookup_way0_valid || !lookup_way1_valid)
      |-> ((WAYS == 1 && lookup_victim_way == 0) ||
           (!lookup_way0_valid && lookup_victim_way == 0) ||
           (lookup_way0_valid && !lookup_way1_valid && lookup_victim_way == 1)));
  a_maintenance_blocks_cpu_acceptance: assert property (@(posedge clk) disable iff (!rst_n)
    (maint_busy || maint_valid) |-> !cpu_req_ready);
  a_cpu_request_stable_while_blocked: assert property (@(posedge clk) disable iff (!rst_n)
    cpu_req_valid && !cpu_req_ready
      |=> $stable({cpu_req_addr, cpu_req_write, cpu_req_wdata,
                   cpu_req_wstrb, cpu_req_size, cpu_req_id}));
  a_no_response_on_reset_release: assert property (@(posedge clk)
    $rose(rst_n) |-> !cpu_rsp_valid);
endmodule

bind l1_dcache_top dcache_protocol_assertions #(.TAG_BITS(TAG_BITS), .WAYS(WAYS))
  u_protocol_assertions (.*);
