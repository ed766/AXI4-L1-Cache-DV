`timescale 1ns/1ps
package dcache_pkg;
  parameter int ADDR_WIDTH = 32;
  parameter int CPU_DATA_WIDTH = 32;
  parameter int AXI_DATA_WIDTH = 64;
  parameter int SETS = 64;
  parameter int WAYS = 2;
  parameter int LINE_BYTES = 32;
  parameter int WORDS_PER_LINE = LINE_BYTES / (CPU_DATA_WIDTH / 8);
  parameter int BEATS_PER_LINE = LINE_BYTES / (AXI_DATA_WIDTH / 8);

  localparam int OFFSET_BITS = $clog2(LINE_BYTES);
  localparam int INDEX_BITS = $clog2(SETS);
  localparam int TAG_BITS = ADDR_WIDTH - OFFSET_BITS - INDEX_BITS;

  typedef enum logic [1:0] {
    MAINT_FLUSH = 2'd0,
    MAINT_INVALIDATE = 2'd1,
    MAINT_FLUSH_INVALIDATE = 2'd2
  } maint_cmd_e;
endpackage
