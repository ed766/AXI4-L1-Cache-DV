`timescale 1ns/1ps

module l1_dcache_nonblocking #(
  parameter int SETS = 16,
  parameter int WAYS = 2,
  parameter int MSHRS = 2,
  parameter int MERGE_DEPTH = 2,
  parameter int RSP_DEPTH = 4
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        cpu_req_valid,
  output logic        cpu_req_ready,
  input  logic [31:0] cpu_req_addr,
  input  logic        cpu_req_write,
  input  logic [31:0] cpu_req_wdata,
  input  logic [3:0]  cpu_req_wstrb,
  input  logic [7:0]  cpu_req_id,

  output logic        cpu_rsp_valid,
  input  logic        cpu_rsp_ready,
  output logic [31:0] cpu_rsp_rdata,
  output logic [7:0]  cpu_rsp_id,
  output logic        cpu_rsp_error,

  output logic [31:0] m_axi_awaddr,
  output logic [1:0]  m_axi_awid,
  output logic [7:0]  m_axi_awlen,
  output logic        m_axi_awvalid,
  input  logic        m_axi_awready,
  output logic [63:0] m_axi_wdata,
  output logic [7:0]  m_axi_wstrb,
  output logic        m_axi_wlast,
  output logic        m_axi_wvalid,
  input  logic        m_axi_wready,
  input  logic [1:0]  m_axi_bid,
  input  logic [1:0]  m_axi_bresp,
  input  logic        m_axi_bvalid,
  output logic        m_axi_bready,

  output logic [31:0] m_axi_araddr,
  output logic [1:0]  m_axi_arid,
  output logic [7:0]  m_axi_arlen,
  output logic        m_axi_arvalid,
  input  logic        m_axi_arready,
  input  logic [1:0]  m_axi_rid,
  input  logic [63:0] m_axi_rdata,
  input  logic [1:0]  m_axi_rresp,
  input  logic        m_axi_rlast,
  input  logic        m_axi_rvalid,
  output logic        m_axi_rready,

  output logic [2:0]  mon_mshr_occupancy,
  output logic [31:0] mon_hits,
  output logic [31:0] mon_misses,
  output logic [31:0] mon_merged,
  output logic [31:0] mon_hit_under_miss,
  output logic [31:0] mon_writebacks
);
  localparam int INDEX_BITS = $clog2(SETS);
  localparam int OFFSET_BITS = 5;
  localparam int TAG_BITS = 32 - INDEX_BITS - OFFSET_BITS;
  localparam int WORDS_PER_LINE = 8;
  localparam int MSHR_BITS = $clog2(MSHRS);
  localparam int RSP_PTR_BITS = $clog2(RSP_DEPTH);

  initial begin
    if (WAYS != 2) $fatal(1, "non-blocking variant currently requires WAYS=2");
    if (MSHRS != 2) $fatal(1, "non-blocking variant currently requires MSHRS=2");
    if (MERGE_DEPTH != 2) $fatal(1, "non-blocking variant currently requires MERGE_DEPTH=2");
    if ((SETS & (SETS - 1)) != 0) $fatal(1, "SETS must be a power of two");
  end

  logic [TAG_BITS-1:0] tags [WAYS][SETS];
  logic valid_bits [WAYS][SETS];
  logic dirty_bits [WAYS][SETS];
  logic [31:0] data_mem [WAYS][SETS][WORDS_PER_LINE];
  logic lru [SETS];

  logic m_valid [MSHRS];
  logic m_ar_sent [MSHRS];
  logic m_refill_done [MSHRS];
  logic m_install_done [MSHRS];
  logic m_error [MSHRS];
  logic m_need_wb [MSHRS];
  logic [31:0] m_line_addr [MSHRS];
  logic [INDEX_BITS-1:0] m_set [MSHRS];
  logic [TAG_BITS-1:0] m_tag [MSHRS];
  logic m_way [MSHRS];
  logic [1:0] m_refill_beat [MSHRS];
  logic [31:0] m_fill [MSHRS][WORDS_PER_LINE];
  logic [1:0] m_req_count [MSHRS];
  logic m_replay_idx [MSHRS];
  logic [7:0] m_req_id [MSHRS][MERGE_DEPTH];
  logic m_req_write [MSHRS][MERGE_DEPTH];
  logic [31:0] m_req_addr [MSHRS][MERGE_DEPTH];
  logic [31:0] m_req_wdata [MSHRS][MERGE_DEPTH];
  logic [3:0] m_req_wstrb [MSHRS][MERGE_DEPTH];

  typedef enum logic [1:0] {WB_IDLE, WB_AW, WB_W, WB_B} wb_state_e;
  wb_state_e wb_state;
  logic [MSHR_BITS-1:0] wb_owner;
  logic [31:0] wb_addr;
  logic [31:0] wb_data [WORDS_PER_LINE];
  logic [1:0] wb_beat;

  logic [31:0] rsp_data [RSP_DEPTH];
  logic [7:0] rsp_id [RSP_DEPTH];
  logic rsp_error [RSP_DEPTH];
  logic [RSP_PTR_BITS-1:0] rsp_rd_ptr, rsp_wr_ptr;
  logic [RSP_PTR_BITS:0] rsp_count;

  wire [INDEX_BITS-1:0] cpu_set = cpu_req_addr[OFFSET_BITS + INDEX_BITS - 1:OFFSET_BITS];
  wire [TAG_BITS-1:0] cpu_tag = cpu_req_addr[31:OFFSET_BITS + INDEX_BITS];
  wire [2:0] cpu_word = cpu_req_addr[4:2];
  wire [31:0] cpu_line_addr = {cpu_req_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
  wire cpu_hit0 = valid_bits[0][cpu_set] && tags[0][cpu_set] == cpu_tag;
  wire cpu_hit1 = valid_bits[1][cpu_set] && tags[1][cpu_set] == cpu_tag;
  wire cpu_hit = cpu_hit0 || cpu_hit1;
  wire cpu_hit_way = cpu_hit1;
  wire cpu_victim_way = !valid_bits[0][cpu_set] ? 1'b0 :
                        !valid_bits[1][cpu_set] ? 1'b1 : lru[cpu_set];
  wire cpu_victim_dirty = valid_bits[cpu_victim_way][cpu_set] &&
                          dirty_bits[cpu_victim_way][cpu_set];

  logic active_line_match;
  logic [MSHR_BITS-1:0] active_line_idx;
  logic active_set_match;
  logic free_mshr_found;
  logic [MSHR_BITS-1:0] free_mshr_idx;
  logic replay_found;
  logic [MSHR_BITS-1:0] replay_mshr_idx;
  logic ar_found;
  logic [MSHR_BITS-1:0] ar_mshr_idx;
  logic [2:0] occupancy;

  function automatic logic [31:0] merge_word(
    input logic [31:0] old_word,
    input logic [31:0] new_word,
    input logic [3:0] strobes
  );
    logic [31:0] result;
    result = old_word;
    for (int byte_idx = 0; byte_idx < 4; byte_idx++)
      if (strobes[byte_idx]) result[byte_idx*8 +: 8] = new_word[byte_idx*8 +: 8];
    return result;
  endfunction

  always_comb begin
    active_line_match = 1'b0;
    active_line_idx = '0;
    active_set_match = 1'b0;
    free_mshr_found = 1'b0;
    free_mshr_idx = '0;
    replay_found = 1'b0;
    replay_mshr_idx = '0;
    ar_found = 1'b0;
    ar_mshr_idx = '0;
    occupancy = '0;
    for (int entry = 0; entry < MSHRS; entry++) begin
      occupancy += 3'(m_valid[entry]);
      if (m_valid[entry] && m_line_addr[entry] == cpu_line_addr && !active_line_match) begin
        active_line_match = 1'b1;
        active_line_idx = MSHR_BITS'(entry);
      end
      if (m_valid[entry] && m_set[entry] == cpu_set) active_set_match = 1'b1;
      if (!m_valid[entry] && !free_mshr_found) begin
        free_mshr_found = 1'b1;
        free_mshr_idx = MSHR_BITS'(entry);
      end
      if (m_valid[entry] && m_refill_done[entry] &&
          (m_error[entry] || m_install_done[entry]) && !replay_found) begin
        replay_found = 1'b1;
        replay_mshr_idx = MSHR_BITS'(entry);
      end
      if (m_valid[entry] && !m_ar_sent[entry] && !m_need_wb[entry] &&
          !m_refill_done[entry] && !ar_found) begin
        ar_found = 1'b1;
        ar_mshr_idx = MSHR_BITS'(entry);
      end
    end
  end

  wire rsp_space = rsp_count < (RSP_PTR_BITS+1)'(RSP_DEPTH);
  wire replay_emit = replay_found && rsp_space;
  wire hit_can_accept = cpu_hit && rsp_space && !replay_emit;
  wire merge_can_accept = active_line_match && !m_refill_done[active_line_idx] &&
                          m_req_count[active_line_idx] < 2'(MERGE_DEPTH);
  wire miss_can_accept = !cpu_hit && !active_line_match && !active_set_match &&
                         free_mshr_found && (!cpu_victim_dirty || wb_state == WB_IDLE);

  always_comb begin
    cpu_req_ready = 1'b0;
    if (rst_n) begin
      if (active_line_match) cpu_req_ready = merge_can_accept;
      else if (cpu_hit) cpu_req_ready = hit_can_accept;
      else cpu_req_ready = miss_can_accept;
    end
  end

  assign cpu_rsp_valid = rsp_count != 0;
  assign cpu_rsp_rdata = rsp_data[rsp_rd_ptr];
  assign cpu_rsp_id = rsp_id[rsp_rd_ptr];
  assign cpu_rsp_error = rsp_error[rsp_rd_ptr];
  assign mon_mshr_occupancy = occupancy;

  always_comb begin
    m_axi_arvalid = ar_found;
    m_axi_arid = 2'(ar_mshr_idx);
    m_axi_araddr = ar_found ? m_line_addr[ar_mshr_idx] : '0;
    m_axi_arlen = 8'd3;
    m_axi_rready = 1'b0;
    if (m_axi_rid < 2'(MSHRS))
      m_axi_rready = m_valid[m_axi_rid[MSHR_BITS-1:0]] &&
                     m_ar_sent[m_axi_rid[MSHR_BITS-1:0]];

    m_axi_awvalid = wb_state == WB_AW;
    m_axi_awaddr = wb_addr;
    m_axi_awid = 2'(wb_owner);
    m_axi_awlen = 8'd3;
    m_axi_wvalid = wb_state == WB_W;
    m_axi_wdata = {wb_data[wb_beat*2+1], wb_data[wb_beat*2]};
    m_axi_wstrb = 8'hff;
    m_axi_wlast = wb_beat == 2'd3;
    m_axi_bready = wb_state == WB_B;
  end

  wire cpu_accept = cpu_req_valid && cpu_req_ready;
  wire cpu_hit_accept = cpu_accept && cpu_hit && !active_line_match;
  wire rsp_dequeue = cpu_rsp_valid && cpu_rsp_ready;
  logic rsp_enqueue;
  logic [31:0] rsp_enqueue_data;
  logic [7:0] rsp_enqueue_id;
  logic rsp_enqueue_error;
  logic [2:0] replay_word;

  always_comb begin
    rsp_enqueue = 1'b0;
    rsp_enqueue_data = '0;
    rsp_enqueue_id = '0;
    rsp_enqueue_error = 1'b0;
    replay_word = '0;
    if (replay_emit) begin
      replay_word = m_req_addr[replay_mshr_idx][m_replay_idx[replay_mshr_idx]][4:2];
      rsp_enqueue = 1'b1;
      rsp_enqueue_id = m_req_id[replay_mshr_idx][m_replay_idx[replay_mshr_idx]];
      rsp_enqueue_error = m_error[replay_mshr_idx];
      if (!m_error[replay_mshr_idx] &&
          !m_req_write[replay_mshr_idx][m_replay_idx[replay_mshr_idx]])
        rsp_enqueue_data = data_mem[m_way[replay_mshr_idx]][m_set[replay_mshr_idx]][replay_word];
    end else if (cpu_hit_accept) begin
      rsp_enqueue = 1'b1;
      rsp_enqueue_id = cpu_req_id;
      rsp_enqueue_data = cpu_req_write ? 32'b0 : data_mem[cpu_hit_way][cpu_set][cpu_word];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rsp_rd_ptr <= '0;
      rsp_wr_ptr <= '0;
      rsp_count <= '0;
      wb_state <= WB_IDLE;
      wb_owner <= '0;
      wb_addr <= '0;
      wb_beat <= '0;
      mon_hits <= '0;
      mon_misses <= '0;
      mon_merged <= '0;
      mon_hit_under_miss <= '0;
      mon_writebacks <= '0;
      for (int entry = 0; entry < MSHRS; entry++) begin
        m_valid[entry] <= 1'b0;
        m_ar_sent[entry] <= 1'b0;
        m_refill_done[entry] <= 1'b0;
        m_install_done[entry] <= 1'b0;
        m_error[entry] <= 1'b0;
        m_need_wb[entry] <= 1'b0;
        m_req_count[entry] <= '0;
        m_replay_idx[entry] <= '0;
        m_refill_beat[entry] <= '0;
      end
      for (int way = 0; way < WAYS; way++) begin
        for (int set_idx = 0; set_idx < SETS; set_idx++) begin
          valid_bits[way][set_idx] <= 1'b0;
          dirty_bits[way][set_idx] <= 1'b0;
        end
      end
      for (int set_idx = 0; set_idx < SETS; set_idx++) lru[set_idx] <= 1'b0;
    end else begin
      if (rsp_enqueue) begin
        rsp_data[rsp_wr_ptr] <= rsp_enqueue_data;
        rsp_id[rsp_wr_ptr] <= rsp_enqueue_id;
        rsp_error[rsp_wr_ptr] <= rsp_enqueue_error;
        rsp_wr_ptr <= rsp_wr_ptr + 1'b1;
      end
      if (rsp_dequeue) rsp_rd_ptr <= rsp_rd_ptr + 1'b1;
      case ({rsp_enqueue, rsp_dequeue})
        2'b10: rsp_count <= rsp_count + 1'b1;
        2'b01: rsp_count <= rsp_count - 1'b1;
        default: rsp_count <= rsp_count;
      endcase

      if (cpu_hit_accept) begin
        mon_hits <= mon_hits + 1'b1;
        if (occupancy != 0) mon_hit_under_miss <= mon_hit_under_miss + 1'b1;
        if (cpu_req_write) begin
          data_mem[cpu_hit_way][cpu_set][cpu_word] <=
              merge_word(data_mem[cpu_hit_way][cpu_set][cpu_word], cpu_req_wdata, cpu_req_wstrb);
          dirty_bits[cpu_hit_way][cpu_set] <= 1'b1;
        end
        lru[cpu_set] <= ~cpu_hit_way;
      end else if (cpu_accept && active_line_match) begin
        int slot;
        slot = int'(m_req_count[active_line_idx]);
        m_req_id[active_line_idx][slot] <= cpu_req_id;
        m_req_write[active_line_idx][slot] <= cpu_req_write;
        m_req_addr[active_line_idx][slot] <= cpu_req_addr;
        m_req_wdata[active_line_idx][slot] <= cpu_req_wdata;
        m_req_wstrb[active_line_idx][slot] <= cpu_req_wstrb;
        m_req_count[active_line_idx] <= m_req_count[active_line_idx] + 1'b1;
        mon_merged <= mon_merged + 1'b1;
      end else if (cpu_accept) begin
        int entry;
        entry = int'(free_mshr_idx);
        m_valid[entry] <= 1'b1;
        m_ar_sent[entry] <= 1'b0;
        m_refill_done[entry] <= 1'b0;
        m_install_done[entry] <= 1'b0;
        m_error[entry] <= 1'b0;
        m_need_wb[entry] <= cpu_victim_dirty;
        m_line_addr[entry] <= cpu_line_addr;
        m_set[entry] <= cpu_set;
        m_tag[entry] <= cpu_tag;
        m_way[entry] <= cpu_victim_way;
        m_refill_beat[entry] <= '0;
        m_req_count[entry] <= 1;
        m_replay_idx[entry] <= '0;
        m_req_id[entry][0] <= cpu_req_id;
        m_req_write[entry][0] <= cpu_req_write;
        m_req_addr[entry][0] <= cpu_req_addr;
        m_req_wdata[entry][0] <= cpu_req_wdata;
        m_req_wstrb[entry][0] <= cpu_req_wstrb;
        mon_misses <= mon_misses + 1'b1;
        if (cpu_victim_dirty) begin
          wb_state <= WB_AW;
          wb_owner <= MSHR_BITS'(entry);
          wb_addr <= {tags[cpu_victim_way][cpu_set], cpu_set, {OFFSET_BITS{1'b0}}};
          wb_beat <= '0;
          for (int word = 0; word < WORDS_PER_LINE; word++)
            wb_data[word] <= data_mem[cpu_victim_way][cpu_set][word];
          mon_writebacks <= mon_writebacks + 1'b1;
        end
        valid_bits[cpu_victim_way][cpu_set] <= 1'b0;
        dirty_bits[cpu_victim_way][cpu_set] <= 1'b0;
      end

      if (m_axi_arvalid && m_axi_arready) m_ar_sent[ar_mshr_idx] <= 1'b1;
      if (m_axi_rvalid && m_axi_rready) begin
        int entry;
        entry = int'(m_axi_rid);
        m_fill[entry][m_refill_beat[entry]*2] <= m_axi_rdata[31:0];
        m_fill[entry][m_refill_beat[entry]*2+1] <= m_axi_rdata[63:32];
        if (m_axi_rresp != 2'b00) m_error[entry] <= 1'b1;
        if (m_axi_rlast || m_refill_beat[entry] == 2'd3) begin
          m_refill_done[entry] <= 1'b1;
          m_refill_beat[entry] <= '0;
        end else begin
          m_refill_beat[entry] <= m_refill_beat[entry] + 1'b1;
        end
      end

      for (int entry = 0; entry < MSHRS; entry++) begin
        if (m_valid[entry] && m_refill_done[entry] && !m_error[entry] && !m_install_done[entry]) begin
          for (int word = 0; word < WORDS_PER_LINE; word++)
            data_mem[m_way[entry]][m_set[entry]][word] <= m_fill[entry][word];
          tags[m_way[entry]][m_set[entry]] <= m_tag[entry];
          valid_bits[m_way[entry]][m_set[entry]] <= 1'b1;
          dirty_bits[m_way[entry]][m_set[entry]] <= 1'b0;
          lru[m_set[entry]] <= ~m_way[entry];
          m_install_done[entry] <= 1'b1;
        end
      end

      if (replay_emit) begin
        int entry;
        int slot;
        logic [2:0] word_idx;
        entry = int'(replay_mshr_idx);
        slot = int'(m_replay_idx[entry]);
        word_idx = m_req_addr[entry][slot][4:2];
        if (!m_error[entry] && m_req_write[entry][slot]) begin
          data_mem[m_way[entry]][m_set[entry]][word_idx] <=
              merge_word(data_mem[m_way[entry]][m_set[entry]][word_idx],
                         m_req_wdata[entry][slot], m_req_wstrb[entry][slot]);
          dirty_bits[m_way[entry]][m_set[entry]] <= 1'b1;
        end
        if (slot + 1 >= m_req_count[entry]) begin
          m_valid[entry] <= 1'b0;
          m_ar_sent[entry] <= 1'b0;
          m_refill_done[entry] <= 1'b0;
          m_install_done[entry] <= 1'b0;
          m_error[entry] <= 1'b0;
          m_need_wb[entry] <= 1'b0;
          m_req_count[entry] <= '0;
          m_replay_idx[entry] <= '0;
        end else begin
          m_replay_idx[entry] <= m_replay_idx[entry] + 1'b1;
        end
      end

      case (wb_state)
        WB_IDLE: ;
        WB_AW: if (m_axi_awready) wb_state <= WB_W;
        WB_W: if (m_axi_wready) begin
          if (m_axi_wlast) begin
            wb_beat <= '0;
            wb_state <= WB_B;
          end else begin
            wb_beat <= wb_beat + 1'b1;
          end
        end
        WB_B: if (m_axi_bvalid && m_axi_bid == 2'(wb_owner)) begin
          if (m_axi_bresp == 2'b00) begin
            m_need_wb[wb_owner] <= 1'b0;
          end else begin
            for (int word = 0; word < WORDS_PER_LINE; word++)
              data_mem[m_way[wb_owner]][m_set[wb_owner]][word] <= wb_data[word];
            tags[m_way[wb_owner]][m_set[wb_owner]] <= wb_addr[31:OFFSET_BITS + INDEX_BITS];
            valid_bits[m_way[wb_owner]][m_set[wb_owner]] <= 1'b1;
            dirty_bits[m_way[wb_owner]][m_set[wb_owner]] <= 1'b1;
            m_need_wb[wb_owner] <= 1'b0;
            m_error[wb_owner] <= 1'b1;
            m_refill_done[wb_owner] <= 1'b1;
          end
          wb_state <= WB_IDLE;
        end
        default: wb_state <= WB_IDLE;
      endcase
    end
  end

  a_wlast_only_final_beat: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_wvalid && m_axi_wlast |-> wb_beat == 2'd3);
  a_refill_waits_for_writeback: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_arvalid |-> !m_need_wb[m_axi_arid[MSHR_BITS-1:0]]);
  a_rid_has_active_mshr: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_rvalid && m_axi_rready |-> m_valid[m_axi_rid[MSHR_BITS-1:0]]);
  a_response_queue_bounded: assert property (@(posedge clk) disable iff (!rst_n)
    rsp_count <= (RSP_PTR_BITS+1)'(RSP_DEPTH));
  a_no_duplicate_active_line: assert property (@(posedge clk) disable iff (!rst_n)
    !(m_valid[0] && m_valid[1] && m_line_addr[0] == m_line_addr[1]));
  a_no_same_set_parallel_miss: assert property (@(posedge clk) disable iff (!rst_n)
    !(m_valid[0] && m_valid[1] && m_set[0] == m_set[1]));
  a_writeback_owner_active: assert property (@(posedge clk) disable iff (!rst_n)
    wb_state != WB_IDLE |-> m_valid[wb_owner]);

endmodule
