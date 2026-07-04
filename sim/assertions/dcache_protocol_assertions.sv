`timescale 1ns/1ps
module dcache_protocol_assertions (
  input logic clk,
  input logic rst_n,
  input logic cpu_req_valid,
  input logic cpu_req_ready,
  input logic cpu_rsp_valid,
  input logic cpu_rsp_ready,
  input logic [31:0] cpu_rsp_rdata,
  input logic [7:0] cpu_rsp_id,
  input logic cpu_rsp_error,
  input logic m_axi_awvalid,
  input logic m_axi_awready,
  input logic [31:0] m_axi_awaddr,
  input logic m_axi_wvalid,
  input logic m_axi_wready,
  input logic [63:0] m_axi_wdata,
  input logic [7:0] m_axi_wstrb,
  input logic m_axi_wlast,
  input logic m_axi_arvalid,
  input logic m_axi_arready,
  input logic [31:0] m_axi_araddr,
  input logic m_axi_rvalid,
  input logic m_axi_rready,
  input logic [63:0] m_axi_rdata,
  input logic [1:0] m_axi_rresp,
  input logic m_axi_rlast
);
  int unsigned accepted_count;
  int unsigned response_count;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      accepted_count <= 0;
      response_count <= 0;
    end else begin
      if (cpu_req_valid && cpu_req_ready) accepted_count <= accepted_count + 1;
      if (cpu_rsp_valid && cpu_rsp_ready) response_count <= response_count + 1;
      a_response_not_ahead: assert (response_count <= accepted_count)
        else $error("CPU response count exceeded accepted request count");
    end
  end

  a_rsp_stable: assert property (@(posedge clk) disable iff (!rst_n)
    cpu_rsp_valid && !cpu_rsp_ready |=>
      $stable({cpu_rsp_rdata, cpu_rsp_id, cpu_rsp_error}));
  a_aw_stable: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_awvalid && !m_axi_awready |=> $stable(m_axi_awaddr));
  a_w_stable: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_wvalid && !m_axi_wready |=> $stable({m_axi_wdata, m_axi_wstrb, m_axi_wlast}));
  a_ar_stable: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_arvalid && !m_axi_arready |=> $stable(m_axi_araddr));
  a_r_stable: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_rvalid && !m_axi_rready |=> $stable({m_axi_rdata, m_axi_rresp, m_axi_rlast}));
endmodule

bind l1_dcache_top dcache_protocol_assertions u_protocol_assertions (.*);
