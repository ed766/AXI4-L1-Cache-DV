`timescale 1ns/1ps

// Integration-only bridge: APB stores retire into a two-entry FIFO while
// coherent loads either forward from the youngest matching store or issue to
// the MSI nodes. Uncached mailbox traffic is never buffered.
module dual_hart_apb_store_buffer #(
  parameter int STORE_DRAIN_DELAY = 3,
  parameter logic [31:0] SHARED_BASE = 32'h8000_0000,
  parameter logic [31:0] SHARED_END  = 32'h8000_ffff,
  parameter logic [31:0] MAILBOX_BASE = 32'h4000_0000,
  parameter logic [31:0] MAILBOX_END  = 32'h4000_0fff
) (
  input  logic clk,
  input  logic rst_n,
  input  logic [1:0][31:0] paddr,
  input  logic [1:0] psel,
  input  logic [1:0] penable,
  input  logic [1:0] pwrite,
  input  logic [1:0][31:0] pwdata,
  output logic [1:0][31:0] prdata,
  output logic [1:0] pready,
  output logic [1:0] pslverr,

  output logic [1:0] coh_req_valid,
  input  logic [1:0] coh_req_ready,
  output logic [1:0] coh_req_write,
  output logic [1:0][31:0] coh_req_addr,
  output logic [1:0][31:0] coh_req_wdata,
  input  logic [1:0] coh_rsp_valid,
  output logic [1:0] coh_rsp_ready,
  input  logic [1:0][31:0] coh_rsp_rdata,
  input  logic [1:0] coh_rsp_error,

  output logic [1:0] fence_done,
  output logic [1:0][1:0] sb_occupancy,
  output logic [1:0][31:0] result_code,
  output logic [1:0] firmware_done,
  output logic [1:0][31:0] observed_value,
  output logic [1:0] store_fault_pending,
  output logic [1:0][31:0] store_fault_addr,
  output logic [31:0] stat_forwarded_loads,
  output logic [31:0] stat_bypassed_loads,
  output logic [31:0] stat_drained_stores
`ifdef FORMAL_OBSERVE
  , output logic [1:0][1:0] formal_sb_count
  , output logic [1:0] formal_forwarded
  , output logic [1:0][31:0] formal_forwarded_data
  , output logic [1:0][31:0] formal_head_addr
  , output logic [1:0][31:0] formal_head_data
  , output logic [1:0] formal_port_busy
  , output logic [1:0] formal_port_is_load
  , output logic [1:0] formal_req_pending
`endif
);
  logic [1:0][1:0][31:0] sb_addr;
  logic [1:0][1:0][31:0] sb_data;
  logic [1:0] sb_head, sb_tail;
  logic [1:0][1:0] sb_count;
  logic [1:0][7:0] sb_age;

  logic [1:0] req_pending;
  logic [1:0] req_is_load;
  logic [1:0][31:0] req_addr_q, req_data_q;
  logic [1:0] port_busy;
  logic [1:0] port_is_load;
  logic [1:0] apb_rsp_valid;
  logic [1:0] apb_rsp_error;
  logic [1:0][31:0] apb_rsp_data;
  logic [31:0] mailbox_mem [0:1023];

  logic [1:0] shared_access, mailbox_access, forwarded;
  logic [1:0][31:0] forwarded_data;
  logic [1:0] enqueue, store_complete;
  logic [1:0] forwarded_count_pulse, bypassed_count_pulse, drained_count_pulse;

`ifdef FORMAL_OBSERVE
  always_comb begin
    formal_sb_count = sb_count;
    formal_forwarded = forwarded;
    formal_forwarded_data = forwarded_data;
    formal_port_busy = port_busy;
    formal_port_is_load = port_is_load;
    formal_req_pending = req_pending;
    for (int formal_hart = 0; formal_hart < 2; formal_hart++) begin
      formal_head_addr[formal_hart] = sb_addr[formal_hart][sb_head[formal_hart]];
      formal_head_data[formal_hart] = sb_data[formal_hart][sb_head[formal_hart]];
    end
  end
`endif

  always_comb begin
    for (int h = 0; h < 2; h++) begin
      shared_access[h] = (paddr[h] >= SHARED_BASE) && (paddr[h] <= SHARED_END);
      mailbox_access[h] = (paddr[h] >= MAILBOX_BASE) && (paddr[h] <= MAILBOX_END);
      forwarded[h] = 1'b0;
      forwarded_data[h] = '0;
      // Scan oldest-to-youngest so the later matching entry wins.
      for (int n = 0; n < 2; n++) begin
        logic idx;
        idx = sb_head[h] ^ n[0];
        if ((n < sb_count[h]) && (sb_addr[h][idx] == paddr[h])) begin
`ifdef COH_MUT_FORWARD_OLDEST
          if (!forwarded[h]) begin
            forwarded[h] = 1'b1;
            forwarded_data[h] = sb_data[h][idx];
          end
`else
          forwarded[h] = 1'b1;
          forwarded_data[h] = sb_data[h][idx];
`endif
        end
      end
`ifdef COH_MUT_BROKEN_FORWARDING
      forwarded[h] = 1'b0;
`endif

      prdata[h] = '0;
      pready[h] = 1'b0;
      pslverr[h] = 1'b0;
      if (psel[h] && penable[h]) begin
        if (mailbox_access[h]) begin
          pready[h] = 1'b1;
          if (paddr[h] == MAILBOX_BASE + 32'h0e0 + 8*h)
            prdata[h] = store_fault_addr[h];
          else if (paddr[h] == MAILBOX_BASE + 32'h0e4 + 8*h)
            prdata[h] = {31'b0, store_fault_pending[h]};
          else
            prdata[h] = mailbox_mem[(paddr[h] - MAILBOX_BASE) >> 2];
        end else if (shared_access[h]) begin
          if (pwrite[h]) begin
            pready[h] = sb_count[h] < 2;
          end else if (forwarded[h]) begin
            pready[h] = 1'b1;
            prdata[h] = forwarded_data[h];
          end else if (apb_rsp_valid[h]) begin
            pready[h] = 1'b1;
            prdata[h] = apb_rsp_data[h];
            pslverr[h] = apb_rsp_error[h];
          end
        end else begin
          pready[h] = 1'b1;
          pslverr[h] = 1'b1;
        end
      end
      enqueue[h] = psel[h] && penable[h] && pwrite[h] && shared_access[h] && pready[h];
`ifdef COH_MUT_FENCE_IGNORES_BUFFER
      fence_done[h] = !req_pending[h] && !port_busy[h];
`else
      fence_done[h] = (sb_count[h] == 0) && !req_pending[h] && !port_busy[h];
`endif
      sb_occupancy[h] = sb_count[h];
      coh_req_valid[h] = req_pending[h];
      coh_req_write[h] = !req_is_load[h];
      coh_req_addr[h] = req_addr_q[h] - SHARED_BASE;
      coh_req_wdata[h] = req_data_q[h];
      coh_rsp_ready[h] = 1'b1;
      store_complete[h] = coh_rsp_valid[h] && port_busy[h] && !port_is_load[h];
      forwarded_count_pulse[h] = psel[h] && penable[h] && !pwrite[h] &&
                                  shared_access[h] && forwarded[h] && pready[h];
      bypassed_count_pulse[h] = psel[h] && penable[h] && !pwrite[h] &&
                                shared_access[h] && !forwarded[h] &&
                                !apb_rsp_valid[h] && !req_pending[h] && !port_busy[h];
      drained_count_pulse[h] = store_complete[h] && !coh_rsp_error[h];
    end
  end

  assign result_code[0] = mailbox_mem[10'h07c]; // 0x1f0 / 4
  assign firmware_done[0] = mailbox_mem[10'h07d][0]; // 0x1f4 / 4
  assign result_code[1] = mailbox_mem[10'h07e]; // 0x1f8 / 4
  assign firmware_done[1] = mailbox_mem[10'h07f][0]; // 0x1fc / 4
  assign observed_value[0] = mailbox_mem[10'h008]; // 0x020 / 4
  assign observed_value[1] = mailbox_mem[10'h009]; // 0x024 / 4

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sb_head <= '0;
      sb_tail <= '0;
      sb_count <= '0;
      sb_age <= '0;
      req_pending <= '0;
      req_is_load <= '0;
      req_addr_q <= '0;
      req_data_q <= '0;
      port_busy <= '0;
      port_is_load <= '0;
      apb_rsp_valid <= '0;
      apb_rsp_error <= '0;
      apb_rsp_data <= '0;
      store_fault_pending <= '0;
      store_fault_addr <= '0;
      stat_forwarded_loads <= '0;
      stat_bypassed_loads <= '0;
      stat_drained_stores <= '0;
      for (int m = 0; m < 1024; m++) mailbox_mem[m] = '0;
    end else begin
      stat_forwarded_loads <= stat_forwarded_loads +
                              32'(forwarded_count_pulse[0]) + 32'(forwarded_count_pulse[1]);
      stat_bypassed_loads <= stat_bypassed_loads +
                             32'(bypassed_count_pulse[0]) + 32'(bypassed_count_pulse[1]);
      stat_drained_stores <= stat_drained_stores +
                             32'(drained_count_pulse[0]) + 32'(drained_count_pulse[1]);
      for (int h = 0; h < 2; h++) begin
        if (sb_count[h] != 0 && sb_age[h] != 8'hff) sb_age[h] <= sb_age[h] + 1'b1;

        if (psel[h] && penable[h] && mailbox_access[h] && pwrite[h] && pready[h]) begin
          if (paddr[h] == MAILBOX_BASE + 32'h0e4 + 8*h && pwdata[h][0]) begin
            store_fault_pending[h] <= 1'b0;
            sb_age[h] <= 8'(STORE_DRAIN_DELAY);
          end else begin
            mailbox_mem[(paddr[h] - MAILBOX_BASE) >> 2] <= pwdata[h];
          end
        end

        if (enqueue[h]) begin
`ifndef COH_MUT_DROP_BUFFERED_STORE
          sb_addr[h][sb_tail[h]] <= paddr[h];
          sb_data[h][sb_tail[h]] <= pwdata[h];
          sb_tail[h] <= sb_tail[h] + 1'b1;
          // A failed drain retains the old head, so a simultaneous enqueue
          // consumes the second slot. Only a successful drain offsets it.
`ifdef COH_MUT_FAILED_ENQUEUE_COUNT
          if (!store_complete[h]) sb_count[h] <= sb_count[h] + 1'b1;
`else
          if (!(store_complete[h] && !coh_rsp_error[h]))
            sb_count[h] <= sb_count[h] + 1'b1;
`endif
          if (sb_count[h] == 0) sb_age[h] <= '0;
`endif
        end

        if (store_complete[h] && !coh_rsp_error[h]) begin
          sb_head[h] <= sb_head[h] + 1'b1;
          if (!enqueue[h]) sb_count[h] <= sb_count[h] - 1'b1;
          sb_age[h] <= '0;
        end
        if (store_complete[h] && coh_rsp_error[h]) begin
          store_fault_pending[h] <= 1'b1;
          store_fault_addr[h] <= sb_addr[h][sb_head[h]];
`ifdef COH_MUT_POP_FAILED_STORE
          sb_head[h] <= sb_head[h] + 1'b1;
          if (!enqueue[h]) sb_count[h] <= sb_count[h] - 1'b1;
`endif
        end

        if (psel[h] && penable[h] && !pwrite[h] && shared_access[h] &&
            !forwarded[h] && !apb_rsp_valid[h] && !req_pending[h] && !port_busy[h]) begin
          req_pending[h] <= 1'b1;
          req_is_load[h] <= 1'b1;
          req_addr_q[h] <= paddr[h];
          req_data_q[h] <= '0;
        end else if (!req_pending[h] && !port_busy[h] &&
`ifndef COH_MUT_IGNORE_STORE_FAULT
                     !store_fault_pending[h] &&
`endif
                     (sb_count[h] != 0) &&
                     (sb_age[h] >= 8'(STORE_DRAIN_DELAY)) &&
                     !(psel[h] && penable[h] && !pwrite[h] && shared_access[h])) begin
          req_pending[h] <= 1'b1;
          req_is_load[h] <= 1'b0;
          req_addr_q[h] <= sb_addr[h][sb_head[h]];
          req_data_q[h] <= sb_data[h][sb_head[h]];
        end

        if (req_pending[h] && coh_req_ready[h]) begin
          req_pending[h] <= 1'b0;
          port_busy[h] <= 1'b1;
          port_is_load[h] <= req_is_load[h];
        end
        if (coh_rsp_valid[h] && port_busy[h]) begin
          port_busy[h] <= 1'b0;
          if (port_is_load[h]) begin
            apb_rsp_valid[h] <= 1'b1;
            apb_rsp_data[h] <= coh_rsp_rdata[h];
            apb_rsp_error[h] <= coh_rsp_error[h];
          end
        end
        if (apb_rsp_valid[h] && psel[h] && penable[h] && pready[h]) begin
          apb_rsp_valid[h] <= 1'b0;
          apb_rsp_error[h] <= 1'b0;
        end
      end
    end
  end

`ifndef SYNTHESIS
  generate for (genvar h = 0; h < 2; h++) begin : g_sb_assertions
    a_store_buffer_bound: assert property (@(posedge clk) disable iff (!rst_n)
      sb_count[h] <= 2);
    a_fence_waits_for_prior_stores: assert property (@(posedge clk) disable iff (!rst_n)
      fence_done[h] |-> (sb_count[h] == 0 && !port_busy[h] && !req_pending[h]));
    a_response_matches_active_port: assert property (@(posedge clk) disable iff (!rst_n)
      coh_rsp_valid[h] |-> port_busy[h]);
    a_forwarding_returns_youngest_match: assert property (@(posedge clk) disable iff (!rst_n)
      psel[h] && penable[h] && !pwrite[h] && shared_access[h] && forwarded[h] |-> pready[h]);
    a_failed_store_preserves_head: assert property (@(posedge clk) disable iff (!rst_n)
      store_complete[h] && coh_rsp_error[h] |=> store_fault_pending[h]);
    a_load_error_is_precise: assert property (@(posedge clk) disable iff (!rst_n)
      apb_rsp_valid[h] && apb_rsp_error[h] |-> pslverr[h]);
  end endgenerate
`endif
endmodule
