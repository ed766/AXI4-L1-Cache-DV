interface cache_cpu_if(input logic clk);
  logic rst_n;
  logic req_valid, req_ready, req_write;
  logic [31:0] req_addr, req_wdata;
  logic [3:0] req_wstrb;
  logic [2:0] req_size;
  logic [7:0] req_id;
  logic rsp_valid, rsp_ready, rsp_error;
  logic [31:0] rsp_rdata;
  logic [7:0] rsp_id;
endinterface

interface cache_maint_if(input logic clk);
  logic valid, ready;
  logic [1:0] cmd;
  logic busy, done, error;
endinterface

interface axi4_mem_if(input logic clk);
  logic [31:0] awaddr, araddr;
  logic [7:0] awlen, arlen;
  logic [2:0] awsize, arsize;
  logic [1:0] awburst, arburst;
  logic awvalid, awready;
  logic [63:0] wdata;
  logic [7:0] wstrb;
  logic wlast, wvalid, wready;
  logic [1:0] bresp;
  logic bvalid, bready;
  logic arvalid, arready;
  logic [63:0] rdata;
  logic [1:0] rresp;
  logic rlast, rvalid, rready;
endinterface

