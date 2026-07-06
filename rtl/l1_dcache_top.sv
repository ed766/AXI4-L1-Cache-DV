`timescale 1ns/1ps
module l1_dcache_top #(
  parameter int SETS = 64,
  parameter int WAYS = 2,
  parameter bit PARITY_ENABLE = 1'b1
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        cpu_req_valid,
  output logic        cpu_req_ready,
  input  logic [31:0] cpu_req_addr,
  input  logic        cpu_req_write,
  input  logic [31:0] cpu_req_wdata,
  input  logic [3:0]  cpu_req_wstrb,
  input  logic [2:0]  cpu_req_size,
  input  logic [7:0]  cpu_req_id,

  output logic        cpu_rsp_valid,
  input  logic        cpu_rsp_ready,
  output logic [31:0] cpu_rsp_rdata,
  output logic [7:0]  cpu_rsp_id,
  output logic        cpu_rsp_error,

  input  logic        maint_valid,
  output logic        maint_ready,
  input  logic [1:0]  maint_cmd,
  output logic        maint_busy,
  output logic        maint_done,
  output logic        maint_error,

  output logic [31:0] m_axi_awaddr,
  output logic [7:0]  m_axi_awlen,
  output logic [2:0]  m_axi_awsize,
  output logic [1:0]  m_axi_awburst,
  output logic        m_axi_awvalid,
  input  logic        m_axi_awready,
  output logic [63:0] m_axi_wdata,
  output logic [7:0]  m_axi_wstrb,
  output logic        m_axi_wlast,
  output logic        m_axi_wvalid,
  input  logic        m_axi_wready,
  input  logic [1:0]  m_axi_bresp,
  input  logic        m_axi_bvalid,
  output logic        m_axi_bready,

  output logic [31:0] m_axi_araddr,
  output logic [7:0]  m_axi_arlen,
  output logic [2:0]  m_axi_arsize,
  output logic [1:0]  m_axi_arburst,
  output logic        m_axi_arvalid,
  input  logic        m_axi_arready,
  input  logic [63:0] m_axi_rdata,
  input  logic [1:0]  m_axi_rresp,
  input  logic        m_axi_rlast,
  input  logic        m_axi_rvalid,
  output logic        m_axi_rready,

  output logic [4:0]  mon_state,
  output logic        mon_hit,
  output logic        mon_miss,
  output logic        mon_evict,
  output logic [1:0]  mon_refill_beat,
  output logic [1:0]  mon_writeback_beat
);
  import dcache_pkg::dcache_state_e;
  import dcache_pkg::ST_IDLE;
  import dcache_pkg::ST_LOOKUP;
  import dcache_pkg::ST_WB_AW;
  import dcache_pkg::ST_WB_W;
  import dcache_pkg::ST_WB_B;
  import dcache_pkg::ST_REFILL_AR;
  import dcache_pkg::ST_REFILL_R;
  import dcache_pkg::ST_REFILL_FINISH;
  import dcache_pkg::ST_REPLAY;
  import dcache_pkg::ST_RESPONSE;
  import dcache_pkg::ST_MAINT_SCAN;
  import dcache_pkg::ST_MAINT_WB_AW;
  import dcache_pkg::ST_MAINT_WB_W;
  import dcache_pkg::ST_MAINT_WB_B;
  localparam int INDEX_BITS = $clog2(SETS);
  localparam int OFFSET_BITS = 5;
  localparam int TAG_BITS = 32 - INDEX_BITS - OFFSET_BITS;
  localparam int WORDS_PER_LINE = 8;
  localparam logic [INDEX_BITS-1:0] LAST_SET = INDEX_BITS'(SETS - 1);

  dcache_state_e state;
  logic [TAG_BITS-1:0] tags [WAYS][SETS];
  logic valid_bits [WAYS][SETS];
  logic dirty_bits [WAYS][SETS];
  logic [31:0] data_mem [WAYS][SETS][WORDS_PER_LINE];
  logic parity_mem [WAYS][SETS][WORDS_PER_LINE];
  logic lru [SETS];
  logic [31:0] refill_buf [WORDS_PER_LINE];

  logic [31:0] req_addr_q, req_wdata_q;
  logic req_write_q;
  logic [3:0] req_wstrb_q;
  logic [2:0] req_size_q;
  logic [7:0] req_id_q;
  logic victim_way;
  logic [INDEX_BITS-1:0] victim_set;
  logic [31:0] wb_addr_q;
  logic [1:0] wb_beat, refill_beat;
  logic refill_error;
  logic maint_active_q;
  logic [1:0] maint_cmd_q;
  logic [INDEX_BITS-1:0] maint_set;
  logic maint_way;
  logic maint_error_q;

  wire [INDEX_BITS-1:0] req_set = req_addr_q[OFFSET_BITS + INDEX_BITS - 1:OFFSET_BITS];
  wire [TAG_BITS-1:0] req_tag = req_addr_q[31:OFFSET_BITS + INDEX_BITS];
  wire [2:0] req_word = req_addr_q[4:2];
  wire req_aligned = (req_size_q <= 3'd2) &&
                     ((req_size_q == 0) ||
                      (req_size_q == 1 && req_addr_q[0] == 0) ||
                      (req_size_q == 2 && req_addr_q[1:0] == 0));
  wire hit0 = valid_bits[0][req_set] && tags[0][req_set] == req_tag;
  wire hit1 = valid_bits[1][req_set] && tags[1][req_set] == req_tag;
  wire hit = hit0 || hit1;
  wire hit_way = hit1;

  function automatic logic word_parity(input logic [31:0] value);
    word_parity = ^value;
  endfunction

  function automatic logic [31:0] merge_word(
    input logic [31:0] old_word,
    input logic [31:0] new_word,
    input logic [3:0] strobes
  );
    logic [31:0] result;
    result = old_word;
    for (int b = 0; b < 4; b++)
      if (strobes[b]) result[b*8 +: 8] = new_word[b*8 +: 8];
    return result;
  endfunction

  function automatic logic choose_victim(input logic [INDEX_BITS-1:0] set_idx);
    if (!valid_bits[0][set_idx])
      choose_victim = 1'b0;
    else if (!valid_bits[1][set_idx])
      choose_victim = 1'b1;
    else
      choose_victim = lru[set_idx];
  endfunction

  wire lookup_victim_way = choose_victim(req_set);
  wire lookup_way0_valid = valid_bits[0][req_set];
  wire lookup_way1_valid = valid_bits[1][req_set];
  wire lookup_victim_valid = valid_bits[lookup_victim_way][req_set];
  wire lookup_victim_dirty = dirty_bits[lookup_victim_way][req_set];
  wire lookup_lru = lru[req_set];
  wire active_victim_valid = valid_bits[victim_way][victim_set];
  wire active_victim_dirty = dirty_bits[victim_way][victim_set];
  wire [TAG_BITS-1:0] active_victim_tag = tags[victim_way][victim_set];
  wire maint_line_valid = valid_bits[maint_way][maint_set];
  wire maint_line_dirty = dirty_bits[maint_way][maint_set];

  assign cpu_req_ready = state == ST_IDLE && !maint_valid;
  assign maint_ready = state == ST_IDLE;
  assign maint_busy = maint_active_q;
  assign mon_state = state;
  assign mon_refill_beat = refill_beat;
  assign mon_writeback_beat = wb_beat;

  always_comb begin
    m_axi_awaddr = wb_addr_q;
    m_axi_awlen = 8'd3;
    m_axi_awsize = 3'd3;
    m_axi_awburst = 2'b01;
    m_axi_awvalid = state == ST_WB_AW || state == ST_MAINT_WB_AW;
    m_axi_wdata = {data_mem[victim_way][victim_set][wb_beat*2+1],
                   data_mem[victim_way][victim_set][wb_beat*2]};
    m_axi_wstrb = 8'hff;
`ifdef CACHE_BUG_WLAST_EARLY
    m_axi_wlast = wb_beat == 2;
`else
    m_axi_wlast = wb_beat == 2'd3;
`endif
    m_axi_wvalid = state == ST_WB_W || state == ST_MAINT_WB_W;
    m_axi_bready = state == ST_WB_B || state == ST_MAINT_WB_B;

    m_axi_araddr = {req_addr_q[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
    m_axi_arlen = 8'd3;
    m_axi_arsize = 3'd3;
    m_axi_arburst = 2'b01;
    m_axi_arvalid = state == ST_REFILL_AR;
    m_axi_rready = state == ST_REFILL_R;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      cpu_rsp_valid <= 1'b0;
      cpu_rsp_rdata <= '0;
      cpu_rsp_id <= '0;
      cpu_rsp_error <= 1'b0;
      maint_done <= 1'b0;
      maint_error <= 1'b0;
      maint_active_q <= 1'b0;
      maint_error_q <= 1'b0;
      wb_beat <= '0;
      refill_beat <= '0;
      refill_error <= 1'b0;
      mon_hit <= 1'b0;
      mon_miss <= 1'b0;
      mon_evict <= 1'b0;
      for (int w = 0; w < WAYS; w++) begin
        for (int s = 0; s < SETS; s++) begin
          valid_bits[w][s] <= 1'b0;
          dirty_bits[w][s] <= 1'b0;
        end
      end
      for (int s = 0; s < SETS; s++) lru[s] <= 1'b0;
    end else begin
      maint_done <= 1'b0;
      mon_hit <= 1'b0;
      mon_miss <= 1'b0;
      mon_evict <= 1'b0;

      if (cpu_rsp_valid && cpu_rsp_ready) cpu_rsp_valid <= 1'b0;

      case (state)
        ST_IDLE: begin
          if (maint_valid) begin
            maint_active_q <= 1'b1;
            maint_cmd_q <= maint_cmd;
            maint_set <= '0;
            maint_way <= 1'b0;
            maint_error_q <= 1'b0;
            maint_error <= 1'b0;
            state <= ST_MAINT_SCAN;
          end else if (cpu_req_valid) begin
            req_addr_q <= cpu_req_addr;
            req_write_q <= cpu_req_write;
            req_wdata_q <= cpu_req_wdata;
            req_wstrb_q <= cpu_req_wstrb;
            req_size_q <= cpu_req_size;
            req_id_q <= cpu_req_id;
            state <= ST_LOOKUP;
          end
        end

        ST_LOOKUP, ST_REPLAY: begin
          if (!req_aligned) begin
            cpu_rsp_rdata <= '0;
            cpu_rsp_id <= req_id_q;
            cpu_rsp_error <= 1'b1;
            cpu_rsp_valid <= 1'b1;
            state <= ST_RESPONSE;
          end else if (hit) begin
            logic [31:0] current_word;
            logic [31:0] updated_word;
            current_word = data_mem[hit_way][req_set][req_word];
            mon_hit <= 1'b1;
            cpu_rsp_id <= req_id_q;
            cpu_rsp_error <= PARITY_ENABLE &&
                             (parity_mem[hit_way][req_set][req_word] != word_parity(current_word));
            if (req_write_q) begin
              updated_word = merge_word(current_word, req_wdata_q, req_wstrb_q);
              data_mem[hit_way][req_set][req_word] <= updated_word;
              parity_mem[hit_way][req_set][req_word] <= word_parity(updated_word);
`ifndef CACHE_BUG_DIRTY_SKIP
              dirty_bits[hit_way][req_set] <= 1'b1;
`endif
              cpu_rsp_rdata <= '0;
            end else begin
              cpu_rsp_rdata <= current_word;
            end
`ifdef CACHE_BUG_LRU_INVERT
            lru[req_set] <= hit_way;
`else
            lru[req_set] <= ~hit_way;
`endif
            cpu_rsp_valid <= 1'b1;
            state <= ST_RESPONSE;
          end else begin
            logic selected_way;
            selected_way = lookup_victim_way;
            victim_way <= selected_way;
            victim_set <= req_set;
            mon_miss <= 1'b1;
            if (valid_bits[selected_way][req_set] && dirty_bits[selected_way][req_set]) begin
              wb_addr_q <= {tags[selected_way][req_set], req_set, {OFFSET_BITS{1'b0}}};
              wb_beat <= '0;
              mon_evict <= 1'b1;
              state <= ST_WB_AW;
            end else begin
              refill_beat <= '0;
              refill_error <= 1'b0;
              state <= ST_REFILL_AR;
            end
          end
        end

        ST_WB_AW: if (m_axi_awready) state <= ST_WB_W;
        ST_WB_W: if (m_axi_wready) begin
          if (m_axi_wlast) begin wb_beat <= '0; state <= ST_WB_B; end
          else wb_beat <= wb_beat + 1'b1;
        end
        ST_WB_B: if (m_axi_bvalid) begin
          if (m_axi_bresp != 2'b00) begin
            cpu_rsp_rdata <= '0;
            cpu_rsp_id <= req_id_q;
            cpu_rsp_error <= 1'b1;
            cpu_rsp_valid <= 1'b1;
            state <= ST_RESPONSE;
          end else begin
            dirty_bits[victim_way][victim_set] <= 1'b0;
            refill_beat <= '0;
            refill_error <= 1'b0;
            state <= ST_REFILL_AR;
          end
        end

        ST_REFILL_AR: if (m_axi_arready) state <= ST_REFILL_R;
        ST_REFILL_R: if (m_axi_rvalid) begin
          refill_buf[refill_beat*2] <= m_axi_rdata[31:0];
          refill_buf[refill_beat*2+1] <= m_axi_rdata[63:32];
`ifndef CACHE_BUG_REFILL_ERROR_IGNORE
          if (m_axi_rresp != 2'b00) refill_error <= 1'b1;
`endif
          if (m_axi_rlast || refill_beat == 2'd3) begin
            state <= ST_REFILL_FINISH;
          end else begin
            refill_beat <= refill_beat + 1'b1;
          end
        end
        ST_REFILL_FINISH: begin
          if (refill_error) begin
            cpu_rsp_rdata <= '0;
            cpu_rsp_id <= req_id_q;
            cpu_rsp_error <= 1'b1;
            cpu_rsp_valid <= 1'b1;
            state <= ST_RESPONSE;
          end else begin
            for (int word = 0; word < WORDS_PER_LINE; word++) begin
              data_mem[victim_way][victim_set][word] <= refill_buf[word];
              parity_mem[victim_way][victim_set][word] <= word_parity(refill_buf[word]);
            end
            tags[victim_way][victim_set] <= req_tag;
            valid_bits[victim_way][victim_set] <= 1'b1;
            dirty_bits[victim_way][victim_set] <= 1'b0;
            lru[req_set] <= ~victim_way;
            state <= ST_REPLAY;
          end
        end

        ST_RESPONSE: if (!cpu_rsp_valid || cpu_rsp_ready) state <= ST_IDLE;

        ST_MAINT_SCAN: begin
          if (maint_set == LAST_SET && maint_way &&
              !(dirty_bits[maint_way][maint_set] && maint_cmd_q != 2'd1)) begin
            if (maint_cmd_q != 2'd0) valid_bits[maint_way][maint_set] <= 1'b0;
            maint_active_q <= 1'b0;
            maint_done <= 1'b1;
            maint_error <= maint_error_q;
            state <= ST_IDLE;
          end else if (dirty_bits[maint_way][maint_set] && maint_cmd_q != 2'd1) begin
            victim_way <= maint_way;
            victim_set <= maint_set;
            wb_addr_q <= {tags[maint_way][maint_set], maint_set, {OFFSET_BITS{1'b0}}};
            wb_beat <= '0;
            state <= ST_MAINT_WB_AW;
          end else begin
            if (maint_cmd_q != 2'd0) valid_bits[maint_way][maint_set] <= 1'b0;
            if (maint_way) begin maint_way <= 1'b0; maint_set <= maint_set + 1'b1; end
            else maint_way <= maint_way + 1'b1;
          end
        end
        ST_MAINT_WB_AW: if (m_axi_awready) state <= ST_MAINT_WB_W;
        ST_MAINT_WB_W: if (m_axi_wready) begin
          if (m_axi_wlast) begin wb_beat <= '0; state <= ST_MAINT_WB_B; end
          else wb_beat <= wb_beat + 1'b1;
        end
        ST_MAINT_WB_B: if (m_axi_bvalid) begin
          if (m_axi_bresp != 2'b00) maint_error_q <= 1'b1;
          else dirty_bits[victim_way][victim_set] <= 1'b0;
          if (maint_cmd_q == 2'd2 && m_axi_bresp == 2'b00)
            valid_bits[victim_way][victim_set] <= 1'b0;
          if (maint_set == LAST_SET && maint_way) begin
            maint_active_q <= 1'b0;
            maint_done <= 1'b1;
            maint_error <= maint_error_q || (m_axi_bresp != 2'b00);
            state <= ST_IDLE;
          end else begin
            if (maint_way) begin maint_way <= 1'b0; maint_set <= maint_set + 1'b1; end
            else maint_way <= maint_way + 1'b1;
            state <= ST_MAINT_SCAN;
          end
        end
        default: state <= ST_IDLE;
      endcase
    end
  end

`ifndef SYNTHESIS
  property p_cpu_response_stable;
    @(posedge clk) disable iff (!rst_n)
      cpu_rsp_valid && !cpu_rsp_ready |=> $stable({cpu_rsp_rdata, cpu_rsp_id, cpu_rsp_error});
  endproperty
  a_cpu_response_stable: assert property (p_cpu_response_stable);

  property p_axi_aw_stable;
    @(posedge clk) disable iff (!rst_n)
      m_axi_awvalid && !m_axi_awready |=> $stable({m_axi_awaddr, m_axi_awlen, m_axi_awsize, m_axi_awburst});
  endproperty
  a_axi_aw_stable: assert property (p_axi_aw_stable);

  property p_axi_w_stable;
    @(posedge clk) disable iff (!rst_n)
      m_axi_wvalid && !m_axi_wready |=> $stable({m_axi_wdata, m_axi_wstrb, m_axi_wlast});
  endproperty
  a_axi_w_stable: assert property (p_axi_w_stable);

  property p_axi_ar_stable;
    @(posedge clk) disable iff (!rst_n)
      m_axi_arvalid && !m_axi_arready |=> $stable({m_axi_araddr, m_axi_arlen, m_axi_arsize, m_axi_arburst});
  endproperty
  a_axi_ar_stable: assert property (p_axi_ar_stable);
`endif
endmodule
