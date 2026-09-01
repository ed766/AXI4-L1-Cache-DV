`timescale 1ns/1ps

// Verification-oriented single-beat transport. Two independent AXI target
// adapters allow different MSI banks to progress concurrently while the
// provenance-locked QoS fabric arbitrates same-bank traffic.
module coherent_axi_qos_transport (
  input  logic clk,
  input  logic rst_n,
  input  logic [1:0] client_req_valid,
  output logic [1:0] client_req_ready,
  input  logic [1:0] client_req_write,
  input  logic [1:0][31:0] client_req_addr,
  input  logic [1:0][31:0] client_req_wdata,
  output logic [1:0] client_rsp_valid,
  input  logic [1:0] client_rsp_ready,
  output logic [1:0][31:0] client_rsp_rdata,
  output logic [1:0] client_rsp_error,
  input  logic [1:0][3:0] hart_qos,
  input  logic [7:0] backpressure_percent,
  input  logic [31:0] schedule_seed,
  input  logic fault_valid,
  input  logic fault_write,
  input  logic [31:0] fault_addr,
  output logic [1:0] home_req_valid,
  input  logic [1:0] home_req_ready,
  output logic [1:0] home_req_write,
  output logic [1:0][31:0] home_req_addr,
  output logic [1:0][31:0] home_req_wdata,
  input  logic [1:0] home_rsp_valid,
  output logic [1:0] home_rsp_ready,
  input  logic [1:0][31:0] home_rsp_rdata,
  output logic [31:0] stat_axi_arbitration_wait,
  output logic [31:0] stat_simultaneous_bank_cycles,
  output logic [1:0][31:0] stat_grants,
  output logic [31:0] stat_age_overrides
);
  localparam int NM = 2;
  localparam int NS = 2;
  localparam int IDW = 2;
  localparam int TIDW = 3;

  typedef enum logic [2:0] {M_IDLE, M_WRITE, M_B, M_READ, M_R, M_RESP} mstate_e;
  typedef enum logic [2:0] {T_IDLE, T_REQ, T_WAIT, T_B, T_R} tstate_e;
  mstate_e mstate [0:1];
  tstate_e tstate [0:1];

  logic [1:0] aw_done, w_done;
  logic [1:0][31:0] req_addr_q, req_data_q, rsp_data_q;
  logic [1:0] rsp_error_q;

  logic [NM-1:0] s_awvalid, s_awready, s_wvalid, s_wready, s_bvalid, s_bready;
  logic [NM-1:0][IDW-1:0] s_awid, s_bid;
  logic [NM-1:0][31:0] s_awaddr;
  logic [NM-1:0][7:0] s_awlen;
  logic [NM-1:0][2:0] s_awsize, s_awprot;
  logic [NM-1:0][1:0] s_awburst, s_bresp;
  logic [NM-1:0][3:0] s_awqos;
  logic [NM-1:0][63:0] s_wdata;
  logic [NM-1:0][7:0] s_wstrb;
  logic [NM-1:0] s_wlast;
  logic [NM-1:0] s_arvalid, s_arready, s_rvalid, s_rready, s_rlast;
  logic [NM-1:0][IDW-1:0] s_arid, s_rid;
  logic [NM-1:0][31:0] s_araddr;
  logic [NM-1:0][7:0] s_arlen;
  logic [NM-1:0][2:0] s_arsize, s_arprot;
  logic [NM-1:0][1:0] s_arburst, s_rresp;
  logic [NM-1:0][3:0] s_arqos;
  logic [NM-1:0][63:0] s_rdata;

  logic [NS-1:0] m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
  logic [NS-1:0][TIDW-1:0] m_awid, m_bid;
  logic [NS-1:0][31:0] m_awaddr;
  logic [NS-1:0][7:0] m_awlen;
  logic [NS-1:0][2:0] m_awsize, m_awprot;
  logic [NS-1:0][1:0] m_awburst, m_bresp;
  logic [NS-1:0][3:0] m_awqos;
  logic [NS-1:0][63:0] m_wdata;
  logic [NS-1:0][7:0] m_wstrb;
  logic [NS-1:0] m_wlast;
  logic [NS-1:0] m_arvalid, m_arready, m_rvalid, m_rready, m_rlast;
  logic [NS-1:0][TIDW-1:0] m_arid, m_rid;
  logic [NS-1:0][31:0] m_araddr;
  logic [NS-1:0][7:0] m_arlen;
  logic [NS-1:0][2:0] m_arsize, m_arprot;
  logic [NS-1:0][1:0] m_arburst, m_rresp;
  logic [NS-1:0][3:0] m_arqos;
  logic [NS-1:0][63:0] m_rdata;
  logic [NS-1:0] mon_ar_age_override, mon_aw_age_override;

  logic [1:0] aw_latched, w_latched, target_write, target_owner, target_error;
  logic [1:0][1:0] reset_ghost_hold;
  logic [1:0][11:0] progress_watchdog;
  logic [1:0] select_write_channel;
  logic [1:0][TIDW-1:0] target_id;
  logic [1:0][31:0] target_addr, target_wdata, target_rdata;
  logic [31:0] stall_lfsr;
  logic [1:0] target_allow;
  logic [1:0] wait_count_pulse;
  logic fault_consumed;

  function automatic logic [31:0] aliased_addr(input logic [31:0] address);
    logic bank;
    begin
      bank = address[4];
`ifdef COH_MUT_BANK_ALIAS
      bank = !bank;
`endif
      aliased_addr = {15'b0, bank, address[15:0]};
    end
  endfunction

  function automatic logic [31:0] restored_addr(input logic [31:0] address);
    restored_addr = {16'b0, address[15:0]};
  endfunction

  always_comb begin
    target_allow[0] = backpressure_percent == 0 ||
                      (int'(stall_lfsr[7:0]) % 100) >= int'(backpressure_percent);
    target_allow[1] = backpressure_percent == 0 ||
                      (int'(stall_lfsr[15:8]) % 100) >= int'(backpressure_percent);

    s_awvalid = '0; s_awid = '0; s_awaddr = '0; s_awlen = '0; s_awsize = '0;
    s_awburst = '0; s_awprot = '0; s_awqos = '0; s_wvalid = '0; s_wdata = '0;
    s_wstrb = '0; s_wlast = '0; s_bready = '0; s_arvalid = '0; s_arid = '0;
    s_araddr = '0; s_arlen = '0; s_arsize = '0; s_arburst = '0; s_arprot = '0;
    s_arqos = '0; s_rready = '0;
    client_req_ready = '0; client_rsp_valid = '0; client_rsp_rdata = rsp_data_q;
    client_rsp_error = rsp_error_q;
    for (int h = 0; h < 2; h++) begin
      client_req_ready[h] = mstate[h] == M_IDLE;
      s_awvalid[h] = mstate[h] == M_WRITE && !aw_done[h];
      s_awid[h] = IDW'(h); s_awaddr[h] = aliased_addr(req_addr_q[h]);
      s_awsize[h] = 3'd2; s_awburst[h] = 2'b01; s_awqos[h] = hart_qos[h];
      // The fabric associates W data through its accepted-AW route FIFO.
      // Present W only after AW acceptance to avoid a combinational
      // ready/route dependency while retaining independent channel stalls.
      s_wvalid[h] = mstate[h] == M_WRITE && aw_done[h] && !w_done[h];
      s_wdata[h] = {2{req_data_q[h]}}; s_wstrb[h] = 8'h0f; s_wlast[h] = 1'b1;
      s_bready[h] = mstate[h] == M_B;
      s_arvalid[h] = mstate[h] == M_READ; s_arid[h] = IDW'(h);
      s_araddr[h] = aliased_addr(req_addr_q[h]); s_arsize[h] = 3'd2;
      s_arburst[h] = 2'b01; s_arqos[h] = hart_qos[h];
      s_rready[h] = mstate[h] == M_R;
      client_rsp_valid[h] = mstate[h] == M_RESP;
      wait_count_pulse[h] = ((mstate[h] == M_WRITE) &&
                             ((s_awvalid[h] && !s_awready[h]) ||
                              (s_wvalid[h] && !s_wready[h]))) ||
                            ((mstate[h] == M_READ) && !s_arready[h]);
    end

    m_awready = '0; m_wready = '0; m_bvalid = '0; m_bid = target_id;
    m_bresp = '0; m_arready = '0; m_rvalid = '0; m_rid = target_id;
    m_rdata = '0; m_rresp = '0; m_rlast = '0;
    for (int bank = 0; bank < 2; bank++) begin
      m_awready[bank] = tstate[bank] == T_IDLE && select_write_channel[bank] &&
                        !aw_latched[bank] && target_allow[bank];
      m_wready[bank] = tstate[bank] == T_IDLE && select_write_channel[bank] &&
                       !w_latched[bank] && target_allow[bank];
      m_arready[bank] = tstate[bank] == T_IDLE && !aw_latched[bank] &&
                        !w_latched[bank] && !select_write_channel[bank] &&
                        target_allow[bank];
      m_bvalid[bank] = tstate[bank] == T_B;
      m_bresp[bank] = target_error[bank] ? 2'b10 : 2'b00;
      m_rvalid[bank] = tstate[bank] == T_R;
      m_rdata[bank] = {2{target_rdata[bank]}};
      m_rresp[bank] = target_error[bank] ? 2'b10 : 2'b00;
      m_rlast[bank] = 1'b1;
    end

    home_req_valid = '0; home_req_write = '0; home_req_addr = '0;
    home_req_wdata = '0; home_rsp_ready = '0;
    for (int bank = 0; bank < 2; bank++) begin
      if (tstate[bank] == T_REQ) begin
        home_req_valid[target_owner[bank]] = 1'b1;
        home_req_write[target_owner[bank]] = target_write[bank];
        home_req_addr[target_owner[bank]] = target_addr[bank];
        home_req_wdata[target_owner[bank]] = target_wdata[bank];
      end
      if (tstate[bank] == T_WAIT)
        home_rsp_ready[target_owner[bank]] = 1'b1;
    end
  end

  axi4_qos_fabric #(
    .NUM_MASTERS(NM), .NUM_SLAVES(NS), .ID_W(IDW), .MAX_OUTSTANDING(2),
    .ROUTE_DEPTH(2), .SLAVE_BASES({32'h0001_0000, 32'h0000_0000}),
    .SLAVE_MASKS({32'hffff_0000, 32'hffff_0000})
  ) fabric (.*);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int h = 0; h < 2; h++) begin
`ifdef COH_MUT_RESET_GHOST_RESPONSE
        mstate[h] <= h == 0 ? M_RESP : M_IDLE;
        reset_ghost_hold[h] <= h == 0 ? 2'd2 : 2'd0;
`else
        mstate[h] <= M_IDLE; aw_done[h] <= 1'b0; w_done[h] <= 1'b0;
        reset_ghost_hold[h] <= '0;
`endif
        aw_done[h] <= 1'b0; w_done[h] <= 1'b0;
        req_addr_q[h] <= '0; req_data_q[h] <= '0; rsp_data_q[h] <= '0;
        rsp_error_q[h] <= 1'b0; stat_grants[h] <= '0;
        progress_watchdog[h] <= '0;
      end
      for (int bank = 0; bank < 2; bank++) begin
        tstate[bank] <= T_IDLE; aw_latched[bank] <= 1'b0; w_latched[bank] <= 1'b0;
        select_write_channel[bank] <= 1'b0;
        target_write[bank] <= 1'b0; target_owner[bank] <= 1'b0;
        target_error[bank] <= 1'b0; target_id[bank] <= '0;
        target_addr[bank] <= '0; target_wdata[bank] <= '0; target_rdata[bank] <= '0;
      end
      stall_lfsr <= schedule_seed ^ 32'h6d2b_79f5;
      fault_consumed <= 1'b0;
      stat_axi_arbitration_wait <= '0;
      stat_simultaneous_bank_cycles <= '0;
      stat_age_overrides <= '0;
    end else begin
      stat_axi_arbitration_wait <= stat_axi_arbitration_wait +
                                   32'(wait_count_pulse[0]) + 32'(wait_count_pulse[1]);
      stall_lfsr <= {stall_lfsr[30:0],
                     stall_lfsr[31] ^ stall_lfsr[21] ^ stall_lfsr[1] ^ stall_lfsr[0]};
      if ((tstate[0] != T_IDLE) && (tstate[1] != T_IDLE))
        stat_simultaneous_bank_cycles <= stat_simultaneous_bank_cycles + 1'b1;
      if (|mon_ar_age_override || |mon_aw_age_override)
        stat_age_overrides <= stat_age_overrides + 1'b1;

      for (int h = 0; h < 2; h++) begin
        if (reset_ghost_hold[h] != 0) reset_ghost_hold[h] <= reset_ghost_hold[h] - 1'b1;
        if (mstate[h] == M_IDLE || (mstate[h] == M_RESP && client_rsp_ready[h]))
          progress_watchdog[h] <= '0;
        else if (progress_watchdog[h] != 12'hfff)
          progress_watchdog[h] <= progress_watchdog[h] + 1'b1;
        if (client_req_valid[h] && client_req_ready[h]) begin
          req_addr_q[h] <= client_req_addr[h]; req_data_q[h] <= client_req_wdata[h];
          aw_done[h] <= 1'b0; w_done[h] <= 1'b0; rsp_error_q[h] <= 1'b0;
          mstate[h] <= client_req_write[h] ? M_WRITE : M_READ;
        end
        if (mstate[h] == M_WRITE) begin
          if (s_awvalid[h] && s_awready[h]) begin
            aw_done[h] <= 1'b1; stat_grants[h] <= stat_grants[h] + 1'b1;
          end
          if (s_wvalid[h] && s_wready[h]) w_done[h] <= 1'b1;
          if ((aw_done[h] || (s_awvalid[h] && s_awready[h])) &&
              (w_done[h] || (s_wvalid[h] && s_wready[h]))) mstate[h] <= M_B;
        end
        if (mstate[h] == M_B && s_bvalid[h] && s_bready[h]) begin
          rsp_error_q[h] <= s_bresp[h] != 0; mstate[h] <= M_RESP;
        end
        if (mstate[h] == M_READ && s_arvalid[h] && s_arready[h]) begin
          stat_grants[h] <= stat_grants[h] + 1'b1; mstate[h] <= M_R;
        end
        if (mstate[h] == M_R && s_rvalid[h] && s_rready[h]) begin
          rsp_data_q[h] <= s_rdata[h][31:0]; rsp_error_q[h] <= s_rresp[h] != 0;
          mstate[h] <= M_RESP;
        end
        if (mstate[h] == M_RESP && client_rsp_ready[h] && reset_ghost_hold[h] == 0)
          mstate[h] <= M_IDLE;
      end

      for (int bank = 0; bank < 2; bank++) begin
        if (tstate[bank] == T_IDLE) begin
          if (!aw_latched[bank] && !w_latched[bank])
            select_write_channel[bank] <= !select_write_channel[bank];
          if (m_awvalid[bank] && m_awready[bank]) begin
            select_write_channel[bank] <= 1'b1;
            aw_latched[bank] <= 1'b1; target_id[bank] <= m_awid[bank];
            target_addr[bank] <= restored_addr(m_awaddr[bank]);
`ifdef COH_MUT_RESPONSE_HART
            target_owner[bank] <= !m_awid[bank][TIDW-1];
`elsif COH_MUT_SWAP_BANK1_OWNER
            target_owner[bank] <= bank == 1 ? !m_awid[bank][TIDW-1] : m_awid[bank][TIDW-1];
`else
            target_owner[bank] <= m_awid[bank][TIDW-1];
`endif
            target_write[bank] <= 1'b1;
          end
          if (m_wvalid[bank] && m_wready[bank]) begin
            select_write_channel[bank] <= 1'b1;
            w_latched[bank] <= 1'b1; target_wdata[bank] <= m_wdata[bank][31:0];
          end
          if (m_arvalid[bank] && m_arready[bank]) begin
`ifdef COH_MUT_AXI_HOME_ID
            target_id[bank] <= m_arid[bank] ^ TIDW'(1 << (TIDW-1));
`else
            target_id[bank] <= m_arid[bank];
`endif
            target_addr[bank] <= restored_addr(m_araddr[bank]);
`ifdef COH_MUT_RESPONSE_HART
            target_owner[bank] <= !m_arid[bank][TIDW-1];
`elsif COH_MUT_SWAP_BANK1_OWNER
            target_owner[bank] <= bank == 1 ? !m_arid[bank][TIDW-1] : m_arid[bank][TIDW-1];
`else
            target_owner[bank] <= m_arid[bank][TIDW-1];
`endif
            target_write[bank] <= 1'b0;
            target_error[bank] <= fault_valid && !fault_consumed && !fault_write &&
                                  restored_addr(m_araddr[bank]) == fault_addr;
            if (fault_valid && !fault_consumed && !fault_write &&
                restored_addr(m_araddr[bank]) == fault_addr) fault_consumed <= 1'b1;
            tstate[bank] <= (fault_valid && !fault_consumed && !fault_write &&
                             restored_addr(m_araddr[bank]) == fault_addr) ? T_R : T_REQ;
          end else if ((aw_latched[bank] || (m_awvalid[bank] && m_awready[bank])) &&
                       (w_latched[bank] || (m_wvalid[bank] && m_wready[bank]))) begin
            logic [31:0] completed_addr;
            completed_addr = (m_awvalid[bank] && m_awready[bank]) ?
                             restored_addr(m_awaddr[bank]) : target_addr[bank];
            aw_latched[bank] <= 1'b0; w_latched[bank] <= 1'b0;
            target_error[bank] <= fault_valid && !fault_consumed && fault_write &&
                                  completed_addr == fault_addr;
            if (fault_valid && !fault_consumed && fault_write && completed_addr == fault_addr)
              fault_consumed <= 1'b1;
            tstate[bank] <= (fault_valid && !fault_consumed && fault_write && completed_addr == fault_addr) ?
                            T_B : T_REQ;
          end
        end else if (tstate[bank] == T_REQ && home_req_ready[target_owner[bank]]) begin
          tstate[bank] <= T_WAIT;
        end else if (tstate[bank] == T_WAIT && home_rsp_valid[target_owner[bank]]) begin
          target_rdata[bank] <= home_rsp_rdata[target_owner[bank]];
          tstate[bank] <= target_write[bank] ? T_B : T_R;
        end else if (tstate[bank] == T_B && m_bready[bank]) begin
          target_error[bank] <= 1'b0; tstate[bank] <= T_IDLE;
        end else if (tstate[bank] == T_R && m_rready[bank]) begin
          target_error[bank] <= 1'b0; tstate[bank] <= T_IDLE;
        end
      end
    end
  end

`ifndef SYNTHESIS
  for (genvar bank = 0; bank < 2; bank++) begin : g_transport_assertions
    a_axi_response_owner_recorded: assert property (@(posedge clk) disable iff (!rst_n)
      (tstate[bank] == T_B || tstate[bank] == T_R) |->
      target_owner[bank] == target_id[bank][TIDW-1]);
    a_bank_alias_matches: assert property (@(posedge clk) disable iff (!rst_n)
      tstate[bank] != T_IDLE |-> target_addr[bank][4] == (bank == 1));
  end
  for (genvar h = 0; h < 2; h++) begin : g_client_assertions
    a_response_stable: assert property (@(posedge clk) disable iff (!rst_n)
      client_rsp_valid[h] && !client_rsp_ready[h] |=>
      $stable(client_rsp_rdata[h]) && $stable(client_rsp_error[h]));
    a_bounded_forward_progress_watchdog: assert property (@(posedge clk) disable iff (!rst_n)
      progress_watchdog[h] != 12'hfff);
  end
  a_no_same_owner_dual_home_request: assert property (@(posedge clk) disable iff (!rst_n)
    !(home_req_valid[0] && home_req_valid[1] && target_owner[0] == target_owner[1]));
  a_simultaneous_home_requests_use_distinct_banks: assert property (
    @(posedge clk) disable iff (!rst_n)
    home_req_valid[0] && home_req_valid[1] |->
      home_req_addr[0][4] != home_req_addr[1][4]);
  for (genvar bank = 0; bank < 2; bank++) begin : g_qos_assertions
    a_age_override_requires_presented_grant: assert property (@(posedge clk) disable iff (!rst_n)
      (mon_ar_age_override[bank] || mon_aw_age_override[bank]) |->
        m_arvalid[bank] || m_awvalid[bank]);
  end
`endif
endmodule
