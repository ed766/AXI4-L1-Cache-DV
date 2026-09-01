`timescale 1ns/1ps
module axi4_qos_fabric #(
    parameter int NUM_MASTERS = 4,
    parameter int NUM_SLAVES = 4,
    parameter int ADDR_W = 32,
    parameter int DATA_W = 64,
    parameter int ID_W = 4,
    parameter int MIDX_W = $clog2(NUM_MASTERS),
    parameter int SIDX_W = $clog2(NUM_SLAVES),
    parameter int TID_W = ID_W + MIDX_W,
    parameter int MAX_OUTSTANDING = 4,
    parameter int ROUTE_DEPTH = 4,
    parameter logic [NUM_SLAVES*ADDR_W-1:0] SLAVE_BASES = {
      32'h3000_0000, 32'h2000_0000, 32'h1000_0000, 32'h0000_0000
    },
    parameter logic [NUM_SLAVES*ADDR_W-1:0] SLAVE_MASKS = {
      32'hFFFF_0000, 32'hFFFF_0000, 32'hFFFF_0000, 32'hFFFF_0000
    },
    parameter logic [NUM_MASTERS*NUM_SLAVES-1:0] MASTER_TARGET_MASK = '1,
    parameter logic [NUM_SLAVES-1:0] SECURE_ONLY = '0
) (
    input logic clk,
    input logic rst_n,

    input  logic [NUM_MASTERS-1:0] s_awvalid,
    output logic [NUM_MASTERS-1:0] s_awready,
    input  logic [NUM_MASTERS-1:0][ID_W-1:0] s_awid,
    input  logic [NUM_MASTERS-1:0][ADDR_W-1:0] s_awaddr,
    input  logic [NUM_MASTERS-1:0][7:0] s_awlen,
    input  logic [NUM_MASTERS-1:0][2:0] s_awsize,
    input  logic [NUM_MASTERS-1:0][1:0] s_awburst,
    input  logic [NUM_MASTERS-1:0][2:0] s_awprot,
    input  logic [NUM_MASTERS-1:0][3:0] s_awqos,
    input  logic [NUM_MASTERS-1:0] s_wvalid,
    output logic [NUM_MASTERS-1:0] s_wready,
    input  logic [NUM_MASTERS-1:0][DATA_W-1:0] s_wdata,
    input  logic [NUM_MASTERS-1:0][DATA_W/8-1:0] s_wstrb,
    input  logic [NUM_MASTERS-1:0] s_wlast,
    output logic [NUM_MASTERS-1:0] s_bvalid,
    input  logic [NUM_MASTERS-1:0] s_bready,
    output logic [NUM_MASTERS-1:0][ID_W-1:0] s_bid,
    output logic [NUM_MASTERS-1:0][1:0] s_bresp,

    input  logic [NUM_MASTERS-1:0] s_arvalid,
    output logic [NUM_MASTERS-1:0] s_arready,
    input  logic [NUM_MASTERS-1:0][ID_W-1:0] s_arid,
    input  logic [NUM_MASTERS-1:0][ADDR_W-1:0] s_araddr,
    input  logic [NUM_MASTERS-1:0][7:0] s_arlen,
    input  logic [NUM_MASTERS-1:0][2:0] s_arsize,
    input  logic [NUM_MASTERS-1:0][1:0] s_arburst,
    input  logic [NUM_MASTERS-1:0][2:0] s_arprot,
    input  logic [NUM_MASTERS-1:0][3:0] s_arqos,
    output logic [NUM_MASTERS-1:0] s_rvalid,
    input  logic [NUM_MASTERS-1:0] s_rready,
    output logic [NUM_MASTERS-1:0][ID_W-1:0] s_rid,
    output logic [NUM_MASTERS-1:0][DATA_W-1:0] s_rdata,
    output logic [NUM_MASTERS-1:0][1:0] s_rresp,
    output logic [NUM_MASTERS-1:0] s_rlast,

    output logic [NUM_SLAVES-1:0] m_awvalid,
    input  logic [NUM_SLAVES-1:0] m_awready,
    output logic [NUM_SLAVES-1:0][TID_W-1:0] m_awid,
    output logic [NUM_SLAVES-1:0][ADDR_W-1:0] m_awaddr,
    output logic [NUM_SLAVES-1:0][7:0] m_awlen,
    output logic [NUM_SLAVES-1:0][2:0] m_awsize,
    output logic [NUM_SLAVES-1:0][1:0] m_awburst,
    output logic [NUM_SLAVES-1:0][2:0] m_awprot,
    output logic [NUM_SLAVES-1:0][3:0] m_awqos,
    output logic [NUM_SLAVES-1:0] m_wvalid,
    input  logic [NUM_SLAVES-1:0] m_wready,
    output logic [NUM_SLAVES-1:0][DATA_W-1:0] m_wdata,
    output logic [NUM_SLAVES-1:0][DATA_W/8-1:0] m_wstrb,
    output logic [NUM_SLAVES-1:0] m_wlast,
    input  logic [NUM_SLAVES-1:0] m_bvalid,
    output logic [NUM_SLAVES-1:0] m_bready,
    input  logic [NUM_SLAVES-1:0][TID_W-1:0] m_bid,
    input  logic [NUM_SLAVES-1:0][1:0] m_bresp,

    output logic [NUM_SLAVES-1:0] m_arvalid,
    input  logic [NUM_SLAVES-1:0] m_arready,
    output logic [NUM_SLAVES-1:0][TID_W-1:0] m_arid,
    output logic [NUM_SLAVES-1:0][ADDR_W-1:0] m_araddr,
    output logic [NUM_SLAVES-1:0][7:0] m_arlen,
    output logic [NUM_SLAVES-1:0][2:0] m_arsize,
    output logic [NUM_SLAVES-1:0][1:0] m_arburst,
    output logic [NUM_SLAVES-1:0][2:0] m_arprot,
    output logic [NUM_SLAVES-1:0][3:0] m_arqos,
    input  logic [NUM_SLAVES-1:0] m_rvalid,
    output logic [NUM_SLAVES-1:0] m_rready,
    input  logic [NUM_SLAVES-1:0][TID_W-1:0] m_rid,
    input  logic [NUM_SLAVES-1:0][DATA_W-1:0] m_rdata,
    input  logic [NUM_SLAVES-1:0][1:0] m_rresp,
    input  logic [NUM_SLAVES-1:0] m_rlast,

    output logic [NUM_SLAVES-1:0] mon_ar_age_override,
    output logic [NUM_SLAVES-1:0] mon_aw_age_override
);
  localparam int ID_COUNT = 1 << ID_W;
  localparam int RPTR_W = $clog2(ROUTE_DEPTH);
  localparam int RCNT_W = $clog2(ROUTE_DEPTH + 1);
  localparam int TARGET_ROUTE_DEPTH = NUM_MASTERS * ROUTE_DEPTH;
  localparam int TWPTR_W = $clog2(TARGET_ROUTE_DEPTH);
  localparam int TWCNT_W = $clog2(TARGET_ROUTE_DEPTH + 1);
  localparam logic [SIDX_W:0] LOCAL_TARGET = {1'b1, {SIDX_W{1'b0}}};

  logic [NUM_MASTERS-1:0][SIDX_W-1:0] aw_target, ar_target;
  logic [NUM_MASTERS-1:0] aw_mapped, ar_mapped, aw_legal, ar_legal;
  logic [NUM_MASTERS-1:0][ID_COUNT-1:0] wr_id_active, rd_id_active;
  logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0] aw_req, ar_req;
  logic [NUM_SLAVES-1:0][NUM_MASTERS*4-1:0] aw_req_qos, ar_req_qos;
  logic [NUM_SLAVES-1:0] aw_gvalid, ar_gvalid;
  logic [NUM_SLAVES-1:0][MIDX_W-1:0] aw_gidx, ar_gidx;

  logic [NUM_MASTERS-1:0][ROUTE_DEPTH-1:0][SIDX_W:0] route_target;
  logic [NUM_MASTERS-1:0][ROUTE_DEPTH-1:0][ID_W-1:0] route_id;
  logic [NUM_MASTERS-1:0][RPTR_W-1:0] route_wptr, route_rptr;
  logic [NUM_MASTERS-1:0][RCNT_W-1:0] route_count;
  logic [NUM_MASTERS-1:0] local_b_pending;
  logic [NUM_MASTERS-1:0][ID_W-1:0] local_bid;

  logic [NUM_MASTERS-1:0] local_r_active;
  logic [NUM_MASTERS-1:0][ID_W-1:0] local_rid;
  logic [NUM_MASTERS-1:0][8:0] local_rbeats;

  logic [NUM_SLAVES-1:0][TARGET_ROUTE_DEPTH-1:0][MIDX_W-1:0] target_w_owner_q;
  logic [NUM_SLAVES-1:0][TWPTR_W-1:0] target_w_wptr, target_w_rptr;
  logic [NUM_SLAVES-1:0][TWCNT_W-1:0] target_w_count;
  logic [NUM_SLAVES-1:0] target_w_push, target_w_pop;
  logic [NUM_MASTERS-1:0] r_lock;
  logic [NUM_MASTERS-1:0][SIDX_W-1:0] r_owner;

  logic [NUM_MASTERS-1:0] route_push;
  logic [NUM_MASTERS-1:0] route_pop;
  logic [NUM_MASTERS-1:0][SIDX_W:0] route_push_target;

  function automatic logic [ADDR_W-1:0] base_at(input int idx);
    base_at = SLAVE_BASES[idx*ADDR_W +: ADDR_W];
  endfunction

  function automatic logic [ADDR_W-1:0] mask_at(input int idx);
    mask_at = SLAVE_MASKS[idx*ADDR_W +: ADDR_W];
  endfunction

  function automatic logic count_below_limit(input logic [ID_COUNT-1:0] bits);
    integer k;
    integer count;
    begin
      count = 0;
      for (k = 0; k < ID_COUNT; k++) count += int'(bits[k]);
      count_below_limit = count < MAX_OUTSTANDING;
    end
  endfunction

  always_comb begin
    aw_target = '0;
    ar_target = '0;
    aw_mapped = '0;
    ar_mapped = '0;
    for (int mi = 0; mi < NUM_MASTERS; mi++) begin
      for (int si = 0; si < NUM_SLAVES; si++) begin
`ifdef BUG_DECODE_BOUNDARY
        if ((s_awaddr[mi] & 32'hF000_0000) == (base_at(si) & 32'hF000_0000)) begin
`else
        if ((s_awaddr[mi] & mask_at(si)) == (base_at(si) & mask_at(si))) begin
`endif
          aw_target[mi] = SIDX_W'(si);
          aw_mapped[mi] = 1'b1;
        end
`ifdef BUG_DECODE_BOUNDARY
        if ((s_araddr[mi] & 32'hF000_0000) == (base_at(si) & 32'hF000_0000)) begin
`else
        if ((s_araddr[mi] & mask_at(si)) == (base_at(si) & mask_at(si))) begin
`endif
          ar_target[mi] = SIDX_W'(si);
          ar_mapped[mi] = 1'b1;
        end
      end
    end
    for (int mi = 0; mi < NUM_MASTERS; mi++) begin
      aw_legal[mi] = aw_mapped[mi]
        && MASTER_TARGET_MASK[mi*NUM_SLAVES + int'(aw_target[mi])]
`ifdef BUG_SECURITY_BYPASS
        && 1'b1
`else
        && (!SECURE_ONLY[aw_target[mi]] || !s_awprot[mi][1])
`endif
        && s_awburst[mi] == 2'b01 && s_awsize[mi] <= 3
        && ((s_awaddr[mi] & ((ADDR_W'(1) << s_awsize[mi]) - 1)) == '0)
        && ({1'b0, s_awaddr[mi][11:0]} + (({5'b0, s_awlen[mi]} + 13'd1) << s_awsize[mi]) <= 13'h1000);
      ar_legal[mi] = ar_mapped[mi]
        && MASTER_TARGET_MASK[mi*NUM_SLAVES + int'(ar_target[mi])]
`ifdef BUG_SECURITY_BYPASS
        && 1'b1
`else
        && (!SECURE_ONLY[ar_target[mi]] || !s_arprot[mi][1])
`endif
        && s_arburst[mi] == 2'b01 && s_arsize[mi] <= 3
        && ((s_araddr[mi] & ((ADDR_W'(1) << s_arsize[mi]) - 1)) == '0)
        && ({1'b0, s_araddr[mi][11:0]} + (({5'b0, s_arlen[mi]} + 13'd1) << s_arsize[mi]) <= 13'h1000);
    end
  end

  always_comb begin
    aw_req = '0;
    ar_req = '0;
    aw_req_qos = '0;
    ar_req_qos = '0;
    for (int si = 0; si < NUM_SLAVES; si++) begin
      for (int mi = 0; mi < NUM_MASTERS; mi++) begin
        aw_req[si][mi] = s_awvalid[mi] && aw_legal[mi] && aw_target[mi] == SIDX_W'(si)
          && int'(route_count[mi]) < ROUTE_DEPTH && !wr_id_active[mi][s_awid[mi]]
          && count_below_limit(wr_id_active[mi]);
        ar_req[si][mi] = s_arvalid[mi] && ar_legal[mi] && ar_target[mi] == SIDX_W'(si)
          && !rd_id_active[mi][s_arid[mi]] && count_below_limit(rd_id_active[mi]);
        aw_req_qos[si][mi*4 +: 4] = s_awqos[mi];
        ar_req_qos[si][mi*4 +: 4] = s_arqos[mi];
      end
    end
  end

  generate
    for (genvar gs = 0; gs < NUM_SLAVES; gs++) begin : g_arbiters
      qos_arbiter #(.REQUESTERS(NUM_MASTERS)) u_aw_arb (
        .clk, .rst_n, .req(aw_req[gs]), .qos_flat(aw_req_qos[gs]),
        .accept(m_awvalid[gs] && m_awready[gs]), .grant_valid(aw_gvalid[gs]),
        .grant_idx(aw_gidx[gs]), .age_override(mon_aw_age_override[gs])
      );
      qos_arbiter #(.REQUESTERS(NUM_MASTERS)) u_ar_arb (
        .clk, .rst_n, .req(ar_req[gs]), .qos_flat(ar_req_qos[gs]),
        .accept(m_arvalid[gs] && m_arready[gs]), .grant_valid(ar_gvalid[gs]),
        .grant_idx(ar_gidx[gs]), .age_override(mon_ar_age_override[gs])
      );
    end
  endgenerate

  always_comb begin
    s_awready = '0;
    s_arready = '0;
    m_awvalid = '0;
    m_awid = '0;
    m_awaddr = '0;
    m_awlen = '0;
    m_awsize = '0;
    m_awburst = '0;
    m_awprot = '0;
    m_awqos = '0;
    m_arvalid = '0;
    m_arid = '0;
    m_araddr = '0;
    m_arlen = '0;
    m_arsize = '0;
    m_arburst = '0;
    m_arprot = '0;
    m_arqos = '0;
    for (int si = 0; si < NUM_SLAVES; si++) begin
      if (aw_gvalid[si]) begin
        m_awvalid[si] = 1'b1;
`ifdef BUG_ID_CORRUPT
        m_awid[si] = {aw_gidx[si] ^ MIDX_W'(1), s_awid[aw_gidx[si]]};
`else
        m_awid[si] = {aw_gidx[si], s_awid[aw_gidx[si]]};
`endif
        m_awaddr[si] = s_awaddr[aw_gidx[si]];
        m_awlen[si] = s_awlen[aw_gidx[si]];
        m_awsize[si] = s_awsize[aw_gidx[si]];
        m_awburst[si] = s_awburst[aw_gidx[si]];
        m_awprot[si] = s_awprot[aw_gidx[si]];
        m_awqos[si] = s_awqos[aw_gidx[si]];
        s_awready[aw_gidx[si]] = m_awready[si];
      end
      if (ar_gvalid[si]) begin
        m_arvalid[si] = 1'b1;
`ifdef BUG_ID_CORRUPT
        m_arid[si] = {ar_gidx[si] ^ MIDX_W'(1), s_arid[ar_gidx[si]]};
`else
        m_arid[si] = {ar_gidx[si], s_arid[ar_gidx[si]]};
`endif
        m_araddr[si] = s_araddr[ar_gidx[si]];
        m_arlen[si] = s_arlen[ar_gidx[si]];
        m_arsize[si] = s_arsize[ar_gidx[si]];
        m_arburst[si] = s_arburst[ar_gidx[si]];
        m_arprot[si] = s_arprot[ar_gidx[si]];
        m_arqos[si] = s_arqos[ar_gidx[si]];
        s_arready[ar_gidx[si]] = m_arready[si];
      end
    end
    for (int mi = 0; mi < NUM_MASTERS; mi++) begin
      if (s_awvalid[mi] && !aw_legal[mi] && int'(route_count[mi]) < ROUTE_DEPTH
          && !wr_id_active[mi][s_awid[mi]] && count_below_limit(wr_id_active[mi]))
        s_awready[mi] = 1'b1;
      if (s_arvalid[mi] && !ar_legal[mi] && !local_r_active[mi]
          && !rd_id_active[mi][s_arid[mi]] && count_below_limit(rd_id_active[mi]))
        s_arready[mi] = 1'b1;
    end
  end

  always_comb begin
    s_wready = '0;
    m_wvalid = '0;
    m_wdata = '0;
    m_wstrb = '0;
    m_wlast = '0;
    route_pop = '0;
    target_w_pop = '0;
    for (int si = 0; si < NUM_SLAVES; si++) begin
      logic selected;
      logic [MIDX_W-1:0] owner;
      owner = target_w_owner_q[si][target_w_rptr[si]];
      selected = target_w_count[si] != 0 && route_count[owner] != 0
        && !route_target[owner][route_rptr[owner]][SIDX_W]
        && route_target[owner][route_rptr[owner]][SIDX_W-1:0] == SIDX_W'(si);
      if (selected) begin
        m_wvalid[si] = s_wvalid[owner];
        m_wdata[si] = s_wdata[owner];
        m_wstrb[si] = s_wstrb[owner];
        m_wlast[si] = s_wlast[owner];
        s_wready[owner] = m_wready[si];
        if (s_wvalid[owner] && m_wready[si]
`ifndef BUG_EARLY_W_UNLOCK
            && s_wlast[owner]
`endif
        ) begin
          route_pop[owner] = 1'b1;
          target_w_pop[si] = 1'b1;
        end
      end
    end
    for (int mi = 0; mi < NUM_MASTERS; mi++) begin
      if (route_count[mi] != 0 && route_target[mi][route_rptr[mi]][SIDX_W]
          && !local_b_pending[mi]) begin
        s_wready[mi] = 1'b1;
        if (s_wvalid[mi] && s_wlast[mi]) route_pop[mi] = 1'b1;
      end
    end
  end

  always_comb begin
    s_bvalid = local_b_pending;
    s_bid = local_bid;
    s_bresp = '1;
    m_bready = '0;
    for (int mi = 0; mi < NUM_MASTERS; mi++) begin
      if (!local_b_pending[mi]) begin
        for (int si = 0; si < NUM_SLAVES; si++) begin
          if (!s_bvalid[mi] && m_bvalid[si]
`ifdef BUG_WRONG_RESPONSE_ROUTE
              && m_bid[si][ID_W +: MIDX_W] == (MIDX_W'(mi) ^ MIDX_W'(1))) begin
`else
              && m_bid[si][ID_W +: MIDX_W] == MIDX_W'(mi)) begin
`endif
            s_bvalid[mi] = 1'b1;
            s_bid[mi] = m_bid[si][ID_W-1:0];
            s_bresp[mi] = m_bresp[si];
            m_bready[si] = s_bready[mi];
          end
        end
      end
    end
  end

  always_comb begin
    s_rvalid = '0;
    s_rid = '0;
    s_rdata = '0;
    s_rresp = '0;
    s_rlast = '0;
    m_rready = '0;
    for (int mi = 0; mi < NUM_MASTERS; mi++) begin
      if (local_r_active[mi]) begin
        s_rvalid[mi] = 1'b1;
        s_rid[mi] = local_rid[mi];
        s_rresp[mi] = 2'b11;
        s_rlast[mi] = local_rbeats[mi] == 1;
      end else if (r_lock[mi]) begin
        s_rvalid[mi] = m_rvalid[r_owner[mi]];
        s_rid[mi] = m_rid[r_owner[mi]][ID_W-1:0];
        s_rdata[mi] = m_rdata[r_owner[mi]];
        s_rresp[mi] = m_rresp[r_owner[mi]];
        s_rlast[mi] = m_rlast[r_owner[mi]];
        m_rready[r_owner[mi]] = s_rready[mi];
      end else begin
        for (int si = 0; si < NUM_SLAVES; si++) begin
          if (!s_rvalid[mi] && m_rvalid[si]
`ifdef BUG_WRONG_RESPONSE_ROUTE
              && m_rid[si][ID_W +: MIDX_W] == (MIDX_W'(mi) ^ MIDX_W'(1))) begin
`else
              && m_rid[si][ID_W +: MIDX_W] == MIDX_W'(mi)) begin
`endif
            s_rvalid[mi] = 1'b1;
            s_rid[mi] = m_rid[si][ID_W-1:0];
            s_rdata[mi] = m_rdata[si];
            s_rresp[mi] = m_rresp[si];
            s_rlast[mi] = m_rlast[si];
            m_rready[si] = s_rready[mi];
          end
        end
      end
    end
  end

  always_comb begin
    route_push = '0;
    route_push_target = '0;
    target_w_push = '0;
    for (int mi = 0; mi < NUM_MASTERS; mi++) begin
      if (s_awvalid[mi] && s_awready[mi]) begin
        route_push[mi] = 1'b1;
        route_push_target[mi] = aw_legal[mi] ? {1'b0, aw_target[mi]} : LOCAL_TARGET;
      end
    end
    for (int si = 0; si < NUM_SLAVES; si++)
      target_w_push[si] = m_awvalid[si] && m_awready[si];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_id_active <= '0;
      rd_id_active <= '0;
      route_wptr <= '0;
      route_rptr <= '0;
      route_count <= '0;
      local_b_pending <= '0;
      local_bid <= '0;
      local_r_active <= '0;
      local_rid <= '0;
      local_rbeats <= '0;
      target_w_owner_q <= '0;
      target_w_wptr <= '0;
      target_w_rptr <= '0;
      target_w_count <= '0;
      r_lock <= '0;
      r_owner <= '0;
    end else begin
      for (int mi = 0; mi < NUM_MASTERS; mi++) begin
        if (s_arvalid[mi] && s_arready[mi]) begin
          rd_id_active[mi][s_arid[mi]] <= 1'b1;
          if (!ar_legal[mi]) begin
            local_r_active[mi] <= 1'b1;
            local_rid[mi] <= s_arid[mi];
            local_rbeats[mi] <= {1'b0, s_arlen[mi]} + 1'b1;
          end
        end
        if (s_rvalid[mi] && s_rready[mi] && s_rlast[mi]) begin
          rd_id_active[mi][s_rid[mi]] <= 1'b0;
          if (local_r_active[mi]) local_r_active[mi] <= 1'b0;
        end else if (local_r_active[mi] && s_rvalid[mi] && s_rready[mi]) begin
          local_rbeats[mi] <= local_rbeats[mi] - 1'b1;
        end

        if (route_push[mi]) begin
          route_target[mi][route_wptr[mi]] <= route_push_target[mi];
          route_id[mi][route_wptr[mi]] <= s_awid[mi];
          route_wptr[mi] <= route_wptr[mi] + 1'b1;
          wr_id_active[mi][s_awid[mi]] <= 1'b1;
        end
        if (route_pop[mi]) begin
          if (route_target[mi][route_rptr[mi]][SIDX_W]) begin
            local_b_pending[mi] <= 1'b1;
            local_bid[mi] <= route_id[mi][route_rptr[mi]];
          end
          route_rptr[mi] <= route_rptr[mi] + 1'b1;
        end
        case ({route_push[mi], route_pop[mi]})
          2'b10: route_count[mi] <= route_count[mi] + 1'b1;
          2'b01: route_count[mi] <= route_count[mi] - 1'b1;
          default: route_count[mi] <= route_count[mi];
        endcase
        if (local_b_pending[mi] && s_bready[mi]) begin
          wr_id_active[mi][local_bid[mi]] <= 1'b0;
          local_b_pending[mi] <= 1'b0;
        end
        for (int si = 0; si < NUM_SLAVES; si++) begin
          if (m_bvalid[si] && m_bready[si] && m_bid[si][ID_W +: MIDX_W] == MIDX_W'(mi))
            wr_id_active[mi][m_bid[si][ID_W-1:0]] <= 1'b0;
        end
      end

      for (int si = 0; si < NUM_SLAVES; si++) begin
        if (target_w_push[si]) begin
          target_w_owner_q[si][target_w_wptr[si]] <= aw_gidx[si];
          target_w_wptr[si] <= target_w_wptr[si] + 1'b1;
        end
        if (target_w_pop[si]) begin
          target_w_rptr[si] <= target_w_rptr[si] + 1'b1;
        end
        case ({target_w_push[si], target_w_pop[si]})
          2'b10: target_w_count[si] <= target_w_count[si] + 1'b1;
          2'b01: target_w_count[si] <= target_w_count[si] - 1'b1;
          default: target_w_count[si] <= target_w_count[si];
        endcase
      end

      for (int mi = 0; mi < NUM_MASTERS; mi++) begin
        if (!local_r_active[mi]) begin
          if (!r_lock[mi]) begin
            for (int si = 0; si < NUM_SLAVES; si++) begin
              if (m_rvalid[si] && m_rid[si][ID_W +: MIDX_W] == MIDX_W'(mi)
                  && !(m_rready[si] && m_rlast[si])) begin
                r_lock[mi] <= 1'b1;
                r_owner[mi] <= SIDX_W'(si);
              end
            end
          end else if (m_rvalid[r_owner[mi]] && m_rready[r_owner[mi]] && m_rlast[r_owner[mi]]) begin
            r_lock[mi] <= 1'b0;
          end
        end
      end
    end
  end
endmodule
