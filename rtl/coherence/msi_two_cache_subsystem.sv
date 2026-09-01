`timescale 1ns/1ps

// Optional educational coherence subsystem. This is deliberately separate from
// l1_dcache_top so the closed single-cache AXI interface remains unchanged.
module msi_two_cache_subsystem #(
  parameter int LINES = 8,
  parameter int WORDS_PER_LINE = 4,
  parameter int MEM_WORDS = 1024
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        c0_req_valid,
  output logic        c0_req_ready,
  input  logic        c0_req_write,
  input  logic [31:0] c0_req_addr,
  input  logic [31:0] c0_req_wdata,
  output logic        c0_rsp_valid,
  input  logic        c0_rsp_ready,
  output logic [31:0] c0_rsp_rdata,

  input  logic        c1_req_valid,
  output logic        c1_req_ready,
  input  logic        c1_req_write,
  input  logic [31:0] c1_req_addr,
  input  logic [31:0] c1_req_wdata,
  output logic        c1_rsp_valid,
  input  logic        c1_rsp_ready,
  output logic [31:0] c1_rsp_rdata,

  input  logic        mem_init_valid,
  input  logic [31:0] mem_init_addr,
  input  logic [31:0] mem_init_data,

  output logic [31:0] stat_read_miss,
  output logic [31:0] stat_write_miss,
  output logic [31:0] stat_invalidations,
  output logic [31:0] stat_interventions,
  output logic [31:0] stat_dirty_writebacks
`ifdef FORMAL_OBSERVE
  , output logic [1:0][LINES-1:0][1:0] formal_line_state
  , output logic [1:0][LINES-1:0][32-$clog2(LINES)-($clog2(WORDS_PER_LINE)+2)-1:0] formal_line_tag
  , output logic [1:0] formal_ctrl_state
  , output logic formal_dirty_victim
`endif
);
  localparam int INDEX_W = $clog2(LINES);
  localparam int OFFSET_W = $clog2(WORDS_PER_LINE) + 2;
  localparam int TAG_W = 32 - INDEX_W - OFFSET_W;
  localparam logic [1:0] MSI_I = 2'b00;
  localparam logic [1:0] MSI_S = 2'b01;
  localparam logic [1:0] MSI_M = 2'b10;

  typedef enum logic [1:0] {CTRL_IDLE, CTRL_EXECUTE, CTRL_RESPOND} ctrl_state_e;
  ctrl_state_e ctrl_state;
  logic rr_select;
  logic req_owner_q;
  logic req_write_q;
  logic [31:0] req_addr_q;
  logic [31:0] req_wdata_q;
  logic [31:0] rsp_data_q;

  logic [1:0] line_state [0:1][0:LINES-1];
  logic [TAG_W-1:0] line_tag [0:1][0:LINES-1];
  logic [31:0] line_data [0:1][0:LINES-1][0:WORDS_PER_LINE-1];
  logic [31:0] backing_mem [0:MEM_WORDS-1];

`ifdef FORMAL_OBSERVE
  always_comb begin
    formal_ctrl_state = ctrl_state;
    formal_dirty_victim = ctrl_state == CTRL_EXECUTE && !local_hit &&
                          line_state[req_owner_q][req_index] == MSI_M;
    for (int formal_cache = 0; formal_cache < 2; formal_cache++) begin
      for (int formal_line = 0; formal_line < LINES; formal_line++) begin
        formal_line_state[formal_cache][formal_line] = line_state[formal_cache][formal_line];
        formal_line_tag[formal_cache][formal_line] = line_tag[formal_cache][formal_line];
      end
    end
  end
`endif

  wire [INDEX_W-1:0] req_index = req_addr_q[OFFSET_W + INDEX_W - 1:OFFSET_W];
  wire [$clog2(WORDS_PER_LINE)-1:0] req_word = req_addr_q[OFFSET_W-1:2];
  wire [TAG_W-1:0] req_tag = req_addr_q[31:OFFSET_W + INDEX_W];
  wire req_other = !req_owner_q;
  wire local_hit = line_state[req_owner_q][req_index] != MSI_I &&
                   line_tag[req_owner_q][req_index] == req_tag;
  wire other_hit = line_state[req_other][req_index] != MSI_I &&
                   line_tag[req_other][req_index] == req_tag;
  wire [31:0] req_line_base = {req_addr_q[31:OFFSET_W], {OFFSET_W{1'b0}}};

  assign c0_req_ready = ctrl_state == CTRL_IDLE && !c0_rsp_valid && !c1_rsp_valid &&
                        (!c1_req_valid || !rr_select);
  assign c1_req_ready = ctrl_state == CTRL_IDLE && !c0_rsp_valid && !c1_rsp_valid &&
                        (!c0_req_valid || rr_select);

  integer cache_id;
  integer line_index;
  integer word_index;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_state <= CTRL_IDLE;
      rr_select <= 1'b0;
      req_owner_q <= 1'b0;
      req_write_q <= 1'b0;
      req_addr_q <= '0;
      req_wdata_q <= '0;
      rsp_data_q <= '0;
      c0_rsp_valid <= 1'b0;
      c1_rsp_valid <= 1'b0;
      c0_rsp_rdata <= '0;
      c1_rsp_rdata <= '0;
      stat_read_miss <= '0;
      stat_write_miss <= '0;
      stat_invalidations <= '0;
      stat_interventions <= '0;
      stat_dirty_writebacks <= '0;
      for (cache_id = 0; cache_id < 2; cache_id++) begin
        for (line_index = 0; line_index < LINES; line_index++) begin
          line_state[cache_id][line_index] <= MSI_I;
          line_tag[cache_id][line_index] <= '0;
          for (word_index = 0; word_index < WORDS_PER_LINE; word_index++)
            line_data[cache_id][line_index][word_index] <= '0;
        end
      end
    end else begin
      if (mem_init_valid && ctrl_state == CTRL_IDLE)
        backing_mem[mem_init_addr[2 +: $clog2(MEM_WORDS)]] <= mem_init_data;

      if (c0_rsp_valid && c0_rsp_ready) c0_rsp_valid <= 1'b0;
      if (c1_rsp_valid && c1_rsp_ready) c1_rsp_valid <= 1'b0;

      case (ctrl_state)
        CTRL_IDLE: begin
          if (c0_req_valid && c0_req_ready) begin
            req_owner_q <= 1'b0;
            req_write_q <= c0_req_write;
            req_addr_q <= c0_req_addr;
            req_wdata_q <= c0_req_wdata;
            rr_select <= 1'b1;
            ctrl_state <= CTRL_EXECUTE;
          end else if (c1_req_valid && c1_req_ready) begin
            req_owner_q <= 1'b1;
            req_write_q <= c1_req_write;
            req_addr_q <= c1_req_addr;
            req_wdata_q <= c1_req_wdata;
            rr_select <= 1'b0;
            ctrl_state <= CTRL_EXECUTE;
          end
        end

        CTRL_EXECUTE: begin
          // A modified victim is committed before its slot is reused.
          if (!local_hit && line_state[req_owner_q][req_index] == MSI_M) begin
`ifndef COH_MUT_SKIP_DIRTY_VICTIM_WB
            for (word_index = 0; word_index < WORDS_PER_LINE; word_index++)
              backing_mem[({line_tag[req_owner_q][req_index], req_index,
                            {OFFSET_W{1'b0}}} >> 2) + word_index] <=
                  line_data[req_owner_q][req_index][word_index];
            stat_dirty_writebacks <= stat_dirty_writebacks + 1'b1;
`endif
          end

          if (!local_hit) begin
            if (req_write_q)
              stat_write_miss <= stat_write_miss + 1'b1;
            else
              stat_read_miss <= stat_read_miss + 1'b1;

            if (other_hit) begin
              if (line_state[req_other][req_index] == MSI_M) begin
`ifndef MSI_MUT_SKIP_INTERVENTION
                for (word_index = 0; word_index < WORDS_PER_LINE; word_index++)
                  backing_mem[(req_line_base >> 2) + word_index] <=
                      line_data[req_other][req_index][word_index];
                stat_interventions <= stat_interventions + 1'b1;
`endif
              end
              for (word_index = 0; word_index < WORDS_PER_LINE; word_index++)
`ifdef COH_MUT_STALE_INTERVENTION
                line_data[req_owner_q][req_index][word_index] <=
                    backing_mem[(req_line_base >> 2) + word_index];
`else
                line_data[req_owner_q][req_index][word_index] <=
                    line_data[req_other][req_index][word_index];
`endif
            end else begin
              for (word_index = 0; word_index < WORDS_PER_LINE; word_index++)
                line_data[req_owner_q][req_index][word_index] <=
                    backing_mem[(req_line_base >> 2) + word_index];
            end
            line_tag[req_owner_q][req_index] <= req_tag;
          end

          if (req_write_q) begin
            if (other_hit) begin
`ifndef MSI_MUT_SKIP_INVALIDATE
              line_state[req_other][req_index] <= MSI_I;
              stat_invalidations <= stat_invalidations + 1'b1;
`else
              line_state[req_other][req_index] <= MSI_M;
`endif
            end
            line_state[req_owner_q][req_index] <= MSI_M;
            line_tag[req_owner_q][req_index] <= req_tag;
            line_data[req_owner_q][req_index][req_word] <= req_wdata_q;
            rsp_data_q <= req_wdata_q;
          end else begin
            if (!local_hit) begin
              line_state[req_owner_q][req_index] <= MSI_S;
`ifndef MSI_MUT_SKIP_DOWNGRADE
              if (other_hit) line_state[req_other][req_index] <= MSI_S;
`endif
              rsp_data_q <= other_hit ? line_data[req_other][req_index][req_word] :
                                          backing_mem[req_addr_q[2 +: $clog2(MEM_WORDS)]];
            end else begin
              rsp_data_q <= line_data[req_owner_q][req_index][req_word];
            end
          end
          ctrl_state <= CTRL_RESPOND;
        end

        CTRL_RESPOND: begin
          if (!req_owner_q && !c0_rsp_valid) begin
            c0_rsp_valid <= 1'b1;
            c0_rsp_rdata <= rsp_data_q;
          end else if (req_owner_q && !c1_rsp_valid) begin
            c1_rsp_valid <= 1'b1;
            c1_rsp_rdata <= rsp_data_q;
          end
          if ((!req_owner_q && (!c0_rsp_valid || c0_rsp_ready)) ||
              (req_owner_q && (!c1_rsp_valid || c1_rsp_ready)))
            ctrl_state <= CTRL_IDLE;
        end
        default: ctrl_state <= CTRL_IDLE;
      endcase
    end
  end

`ifndef SYNTHESIS
  generate
    for (genvar set_idx = 0; set_idx < LINES; set_idx++) begin : g_msi_assertions
      a_single_modified_owner: assert property (@(posedge clk) disable iff (!rst_n)
        !(line_state[0][set_idx] == MSI_M && line_state[1][set_idx] == MSI_M &&
          line_tag[0][set_idx] == line_tag[1][set_idx]));
    end
  endgenerate
  a_no_simultaneous_accept: assert property (@(posedge clk) disable iff (!rst_n)
    !((c0_req_valid && c0_req_ready) && (c1_req_valid && c1_req_ready)));
  a_response_owner_exclusive: assert property (@(posedge clk) disable iff (!rst_n)
    !(c0_rsp_valid && c1_rsp_valid));
`endif

  initial begin
    if ((LINES & (LINES - 1)) != 0) $fatal(1, "LINES must be a power of two");
    if ((WORDS_PER_LINE & (WORDS_PER_LINE - 1)) != 0)
      $fatal(1, "WORDS_PER_LINE must be a power of two");
  end
endmodule
