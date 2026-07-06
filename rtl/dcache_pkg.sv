`timescale 1ns/1ps
package dcache_pkg;
  typedef enum logic [1:0] {
    MAINT_FLUSH = 2'd0,
    MAINT_INVALIDATE = 2'd1,
    MAINT_FLUSH_INVALIDATE = 2'd2
  } maint_cmd_e;

  typedef enum logic [4:0] {
    ST_IDLE, ST_LOOKUP, ST_WB_AW, ST_WB_W, ST_WB_B,
    ST_REFILL_AR, ST_REFILL_R, ST_REFILL_FINISH, ST_REPLAY,
    ST_RESPONSE, ST_MAINT_SCAN, ST_MAINT_WB_AW, ST_MAINT_WB_W,
    ST_MAINT_WB_B
  } dcache_state_e;
endpackage
