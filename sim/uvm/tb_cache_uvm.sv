`timescale 1ns/1ps
module tb_cache_uvm;
  import uvm_pkg::*;
  import cache_uvm_pkg::*;

  logic clk = 0;
  always #5 clk = ~clk;
  cache_cpu_if cpu_if(clk);
  cache_maint_if maint_if(clk);
  axi4_mem_if axi_if(clk);
  logic [4:0] mon_state;
  logic mon_hit, mon_miss, mon_evict;
  logic [1:0] mon_refill_beat, mon_writeback_beat;

  l1_dcache_top dut (
    .clk, .rst_n(cpu_if.rst_n),
    .cpu_req_valid(cpu_if.req_valid), .cpu_req_ready(cpu_if.req_ready),
    .cpu_req_addr(cpu_if.req_addr), .cpu_req_write(cpu_if.req_write),
    .cpu_req_wdata(cpu_if.req_wdata), .cpu_req_wstrb(cpu_if.req_wstrb),
    .cpu_req_size(cpu_if.req_size), .cpu_req_id(cpu_if.req_id),
    .cpu_rsp_valid(cpu_if.rsp_valid), .cpu_rsp_ready(cpu_if.rsp_ready),
    .cpu_rsp_rdata(cpu_if.rsp_rdata), .cpu_rsp_id(cpu_if.rsp_id),
    .cpu_rsp_error(cpu_if.rsp_error),
    .maint_valid(maint_if.valid), .maint_ready(maint_if.ready), .maint_cmd(maint_if.cmd),
    .maint_busy(maint_if.busy), .maint_done(maint_if.done), .maint_error(maint_if.error),
    .m_axi_awaddr(axi_if.awaddr), .m_axi_awlen(axi_if.awlen),
    .m_axi_awsize(axi_if.awsize), .m_axi_awburst(axi_if.awburst),
    .m_axi_awvalid(axi_if.awvalid), .m_axi_awready(axi_if.awready),
    .m_axi_wdata(axi_if.wdata), .m_axi_wstrb(axi_if.wstrb),
    .m_axi_wlast(axi_if.wlast), .m_axi_wvalid(axi_if.wvalid), .m_axi_wready(axi_if.wready),
    .m_axi_bresp(axi_if.bresp), .m_axi_bvalid(axi_if.bvalid), .m_axi_bready(axi_if.bready),
    .m_axi_araddr(axi_if.araddr), .m_axi_arlen(axi_if.arlen),
    .m_axi_arsize(axi_if.arsize), .m_axi_arburst(axi_if.arburst),
    .m_axi_arvalid(axi_if.arvalid), .m_axi_arready(axi_if.arready),
    .m_axi_rdata(axi_if.rdata), .m_axi_rresp(axi_if.rresp),
    .m_axi_rlast(axi_if.rlast), .m_axi_rvalid(axi_if.rvalid), .m_axi_rready(axi_if.rready),
    .mon_state, .mon_hit, .mon_miss, .mon_evict, .mon_refill_beat, .mon_writeback_beat
  );

  initial begin
    cpu_if.rst_n = 0;
    cpu_if.req_valid = 0;
    cpu_if.rsp_ready = 1;
    maint_if.valid = 0;
    maint_if.cmd = 0;
    repeat (5) @(posedge clk);
    cpu_if.rst_n = 1;
  end

  initial begin
    uvm_coreservice_t core_service;
    cache_noop_component_visitor visitor;
    cache_uvm_pkg::g_cpu_vif = cpu_if;
    cache_uvm_pkg::g_axi_vif = axi_if;
    core_service = uvm_coreservice_t::get();
    visitor = new("visitor");
    core_service.set_component_visitor(visitor);
    run_test("cache_smoke_test");
  end
endmodule
