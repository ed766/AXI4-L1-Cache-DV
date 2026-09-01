`timescale 1ns/1ps

module tb_coherent_transport;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic [1:0] client_req_valid, client_req_ready, client_req_write;
  logic [1:0][31:0] client_req_addr, client_req_wdata;
  logic [1:0] client_rsp_valid, client_rsp_ready, client_rsp_error;
  logic [1:0][31:0] client_rsp_rdata;
  logic [1:0][3:0] hart_qos;
  logic [7:0] backpressure_percent;
  logic [31:0] schedule_seed;
  logic fault_valid, fault_write;
  logic [31:0] fault_addr;
  logic [1:0] home_req_valid, home_req_ready, home_req_write;
  logic [1:0][31:0] home_req_addr, home_req_wdata;
  logic [1:0] home_rsp_valid, home_rsp_ready;
  logic [1:0][31:0] home_rsp_rdata;
  logic [31:0] stat_axi_arbitration_wait, stat_simultaneous_bank_cycles;
  logic [1:0][31:0] stat_grants;
  logic [31:0] stat_age_overrides;
  integer issued [0:1], completed [0:1], service [0:1], max_gap [0:1], gap [0:1];
  integer response_stalls;
  integer pending_delay [0:1];
  integer count, cycles, bp, q0, q1, address1, event_fd;
  logic [1:0] leaf_req;
  logic [7:0] leaf_qos;
  logic leaf_accept, leaf_grant_valid, leaf_age_override;
  logic leaf_grant_idx;
  integer leaf_age_overrides, leaf_first_grant;
  string test_name, event_file;

  coherent_axi_qos_transport dut (.*);
  qos_arbiter #(.REQUESTERS(2)) leaf_age_dut (
    .clk, .rst_n, .req(leaf_req), .qos_flat(leaf_qos), .accept(leaf_accept),
    .grant_valid(leaf_grant_valid), .grant_idx(leaf_grant_idx),
    .age_override(leaf_age_override)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      home_rsp_valid <= '0;
      home_rsp_rdata <= '0;
      pending_delay[0] <= 0; pending_delay[1] <= 0;
    end else begin
      for (int h = 0; h < 2; h++) begin
        if (home_rsp_valid[h] && home_rsp_ready[h]) home_rsp_valid[h] <= 1'b0;
        if (home_req_valid[h] && home_req_ready[h]) pending_delay[h] <= 3;
        else if (pending_delay[h] > 1) pending_delay[h] <= pending_delay[h] - 1;
        else if (pending_delay[h] == 1) begin
          pending_delay[h] <= 0; home_rsp_valid[h] <= 1'b1;
          home_rsp_rdata[h] <= 32'h600d_0000 | h;
        end
      end
    end
  end

  always @(posedge clk) begin
    if (rst_n) begin
      if (leaf_grant_valid && leaf_accept) begin
        if (leaf_first_grant < 0) leaf_first_grant = int'(leaf_grant_idx);
        if (leaf_age_override) leaf_age_overrides++;
      end
      for (int h = 0; h < 2; h++) begin
        if (client_req_valid[h] && client_req_ready[h]) begin
          issued[h]++;
          $fwrite(event_fd, "%0d,1,transport_request,%0d,%0d,%08x,%08x,%0d,%0d\n",
                  cycles, h, client_req_addr[h][4], client_req_addr[h], client_req_wdata[h],
                  client_req_write[h], hart_qos[h]);
        end
        if (client_rsp_valid[h] && client_rsp_ready[h]) begin
          completed[h]++;
          $fwrite(event_fd, "%0d,1,transport_response,%0d,-1,00000000,%08x,0,%0d\n",
                  cycles, h, client_rsp_rdata[h], client_rsp_error[h]);
        end
        if (client_rsp_valid[h] && !client_rsp_ready[h]) begin
          response_stalls++;
          $fwrite(event_fd, "%0d,1,response_stall,%0d,-1,00000000,%08x,0,%0d\n",
                  cycles, h, client_rsp_rdata[h], client_rsp_error[h]);
        end
        if (dut.s_awvalid[h] && dut.s_awready[h])
          $fwrite(event_fd, "%0d,1,axi_aw_grant,%0d,%0d,%08x,%08x,%0d,%0d\n",
                  cycles, h, dut.s_awaddr[h][16], dut.s_awaddr[h], dut.s_wdata[h][31:0],
                  hart_qos[h], dut.mon_aw_age_override[dut.s_awaddr[h][16]]);
        if (dut.s_arvalid[h] && dut.s_arready[h]) begin
          service[h]++; gap[h] = 0; gap[1-h]++;
          if (gap[1-h] > max_gap[1-h]) max_gap[1-h] = gap[1-h];
          $fwrite(event_fd, "%0d,1,axi_ar_grant,%0d,%0d,%08x,00000000,%0d,%0d\n",
                  cycles, h, dut.s_araddr[h][16], dut.s_araddr[h], hart_qos[h],
                  dut.mon_ar_age_override[dut.s_araddr[h][16]]);
        end
      end
      if (dut.tstate[0] != 0 && dut.tstate[1] != 0)
        $fwrite(event_fd, "%0d,1,simultaneous_banks,-1,-1,00000000,00000000,0,0\n", cycles);
      if (leaf_grant_valid && leaf_accept)
        $fwrite(event_fd, "%0d,1,leaf_qos_grant,%0d,-1,00000000,00000000,%0d,%0d\n",
                cycles, leaf_grant_idx, leaf_qos[leaf_grant_idx*4 +: 4], leaf_age_override);
    end
  end

  initial begin
    test_name = "different_bank"; event_file = "coherent_transport_events.csv";
    count = 40; bp = 0; q0 = 4; q1 = 4; address1 = 16;
    void'($value$plusargs("TEST=%s", test_name));
    void'($value$plusargs("EVENT_TRACE_FILE=%s", event_file));
    void'($value$plusargs("COUNT=%d", count));
    void'($value$plusargs("BACKPRESSURE=%d", bp));
    if (test_name == "same_bank_equal") address1 = 0;
    if (test_name == "mixed_qos" || test_name == "starvation_override") begin
      address1 = 0; q0 = 0; q1 = 15;
    end
    client_req_valid = '0; client_req_write = '0; client_req_addr = '0;
    client_req_wdata = '0; client_rsp_ready = '1;
    if (test_name == "write_response_backpressure") begin
      client_req_write = '1; client_req_wdata[0] = 32'h1111_aaaa;
      client_req_wdata[1] = 32'h2222_bbbb; count = 8;
    end
    if (test_name == "read_response_backpressure") count = 8;
    hart_qos[0] = 4'(q0); hart_qos[1] = 4'(q1);
    backpressure_percent = 8'(bp); schedule_seed = 32'h1234_5678;
    fault_valid = 0; fault_write = 0; fault_addr = 0;
    leaf_req = '0; leaf_qos = 8'hf0; leaf_accept = 1'b0;
    leaf_age_overrides = 0; leaf_first_grant = -1; response_stalls = 0;
    home_req_ready = '1; home_rsp_valid = '0; home_rsp_rdata = '0;
    for (int h = 0; h < 2; h++) begin
      issued[h] = 0; completed[h] = 0; service[h] = 0; max_gap[h] = 0; gap[h] = 0;
      pending_delay[h] = 0;
    end
    event_fd = $fopen(event_file, "w");
    $fwrite(event_fd, "cycle,epoch,event,hart,bank,address,data,detail0,detail1\n");
    client_req_addr[0] = 0; client_req_addr[1] = address1;
    repeat (5) @(posedge clk); rst_n = 1;
    if (test_name == "mixed_qos") begin leaf_req = 2'b11; leaf_accept = 1'b1; end
    if (test_name == "starvation_override") begin leaf_req = 2'b11; leaf_accept = 1'b1; end
    cycles = 0;
    while ((completed[0] < count || completed[1] < count) && cycles < 20000) begin
      @(negedge clk);
      for (int h = 0; h < 2; h++) client_req_valid[h] = issued[h] < count;
      if (test_name == "read_response_backpressure" || test_name == "write_response_backpressure")
        client_rsp_ready = (cycles % 4 == 0) ? 2'b00 : 2'b11;
      cycles++;
    end
    client_req_valid = '0; client_rsp_ready = '1;
    $display("TRANSPORT_SUMMARY|test=%s|status=%s|cycles=%0d|service0=%0d|service1=%0d|max_gap0=%0d|max_gap1=%0d|simultaneous=%0d|age_overrides=%0d|wait=%0d|leaf_first_grant=%0d|response_stalls=%0d",
      test_name, (completed[0] == count && completed[1] == count) ? "PASS" : "FAIL",
      cycles, service[0], service[1], max_gap[0], max_gap[1],
      stat_simultaneous_bank_cycles, stat_age_overrides + leaf_age_overrides,
      stat_axi_arbitration_wait, leaf_first_grant, response_stalls);
    if (completed[0] != count || completed[1] != count) $fatal(1, "transport timeout");
    if (test_name == "different_bank" && stat_simultaneous_bank_cycles == 0)
      $fatal(1, "no different-bank overlap");
    if (test_name == "mixed_qos" && leaf_first_grant != 1)
      $fatal(1, "high QoS request did not win first");
    if (test_name == "starvation_override" && leaf_age_overrides == 0)
      $fatal(1, "aging override not observed");
    if ((test_name == "read_response_backpressure" || test_name == "write_response_backpressure") &&
        response_stalls == 0) $fatal(1, "response backpressure not observed");
    $fclose(event_fd);
    $finish;
  end
endmodule
