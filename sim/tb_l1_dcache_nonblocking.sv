`timescale 1ns/1ps

module tb_l1_dcache_nonblocking;
  localparam int SETS = 16;
  localparam int MEM_WORDS = 16384;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic cpu_req_valid, cpu_req_ready, cpu_req_write;
  logic [31:0] cpu_req_addr, cpu_req_wdata;
  logic [3:0] cpu_req_wstrb;
  logic [7:0] cpu_req_id;
  logic cpu_rsp_valid, cpu_rsp_ready, cpu_rsp_error;
  logic [31:0] cpu_rsp_rdata;
  logic [7:0] cpu_rsp_id;

  logic [31:0] m_axi_awaddr, m_axi_araddr;
  logic [1:0] m_axi_awid, m_axi_bid, m_axi_arid, m_axi_rid;
  logic [7:0] m_axi_awlen, m_axi_arlen;
  logic m_axi_awvalid, m_axi_awready, m_axi_wlast, m_axi_wvalid, m_axi_wready;
  logic [63:0] m_axi_wdata, m_axi_rdata;
  logic [7:0] m_axi_wstrb;
  logic [1:0] m_axi_bresp, m_axi_rresp;
  logic m_axi_bvalid, m_axi_bready, m_axi_arvalid, m_axi_arready;
  logic m_axi_rlast, m_axi_rvalid, m_axi_rready;
  logic [2:0] mon_mshr_occupancy;
  logic [31:0] mon_hits, mon_misses, mon_merged, mon_hit_under_miss, mon_writebacks;

  l1_dcache_nonblocking #(.SETS(SETS)) dut (.*);

  logic [31:0] backing_mem [MEM_WORDS];
  logic [31:0] golden_mem [MEM_WORDS];
  logic read_active [2];
  logic [31:0] read_addr [2];
  logic [1:0] read_beat [2];
  integer read_delay [2];
  integer configured_delay [2];
  logic write_active;
  logic [31:0] write_addr;
  logic [1:0] write_id;
  logic [1:0] write_beat;
  logic [63:0] write_buffer [4];
  logic pending_b;
  logic [1:0] pending_b_id;
  logic [1:0] pending_b_resp;
  logic inject_read_error;
  logic [31:0] inject_read_line;
  logic inject_write_error;
  logic force_ar_stall;
  logic force_aw_stall;
  logic force_w_stall;

  logic expected_valid [256];
  logic expected_error [256];
  logic [31:0] expected_data [256];
  logic response_seen [256];
  integer response_order [256];
  integer request_count, response_count, checks, failures, cycles;
  integer ar_count, aw_count, max_mshrs;
  string test_name;

  function automatic logic [31:0] merged(
    input logic [31:0] old_word,
    input logic [31:0] new_word,
    input logic [3:0] strobes
  );
    logic [31:0] value;
    value = old_word;
    for (int byte_idx = 0; byte_idx < 4; byte_idx++)
      if (strobes[byte_idx]) value[byte_idx*8 +: 8] = new_word[byte_idx*8 +: 8];
    return value;
  endfunction

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) begin
      failures++;
      $display("NB_CHECK_FAIL|test=%s|message=%s|cycle=%0d", test_name, message, cycles);
    end
  endtask

  task automatic clear_scoreboard;
    for (int id = 0; id < 256; id++) begin
      expected_valid[id] = 1'b0;
      expected_error[id] = 1'b0;
      expected_data[id] = '0;
      response_seen[id] = 1'b0;
      response_order[id] = -1;
    end
    request_count = 0;
    response_count = 0;
  endtask

  task automatic reset_dut(input logic clear_expected);
    cpu_req_valid = 1'b0;
    cpu_rsp_ready = 1'b1;
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
    if (clear_expected) clear_scoreboard();
  endtask

  task automatic issue(
    input logic [31:0] addr,
    input logic write,
    input logic [31:0] wdata,
    input logic [3:0] wstrb,
    input logic [7:0] id,
    input logic expect_error
  );
    int word_idx;
    word_idx = addr >> 2;
    @(negedge clk);
    cpu_req_valid = 1'b1;
    cpu_req_addr = addr;
    cpu_req_write = write;
    cpu_req_wdata = wdata;
    cpu_req_wstrb = wstrb;
    cpu_req_id = id;
    do @(posedge clk); while (!cpu_req_ready);
    expected_valid[id] = 1'b1;
    expected_error[id] = expect_error;
    expected_data[id] = write ? 32'b0 : golden_mem[word_idx];
    if (write && !expect_error) golden_mem[word_idx] = merged(golden_mem[word_idx], wdata, wstrb);
    request_count++;
    @(negedge clk);
    cpu_req_valid = 1'b0;
  endtask

  task automatic wait_id(input logic [7:0] id);
    int timeout;
    timeout = 0;
    while (!response_seen[id] && timeout < 2000) begin
      @(posedge clk);
      timeout++;
    end
    check(response_seen[id], $sformatf("response timeout for id %0d", id));
  endtask

  task automatic wait_all;
    int timeout;
    timeout = 0;
    while (response_count < request_count && timeout < 5000) begin
      @(posedge clk);
      timeout++;
    end
    check(response_count == request_count, "all accepted requests produced responses");
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axi_rvalid <= 1'b0;
      m_axi_rid <= '0;
      m_axi_rdata <= '0;
      m_axi_rresp <= '0;
      m_axi_rlast <= 1'b0;
      m_axi_bvalid <= 1'b0;
      m_axi_bid <= '0;
      m_axi_bresp <= '0;
      write_active <= 1'b0;
      pending_b <= 1'b0;
      write_beat <= '0;
      for (int slot = 0; slot < 2; slot++) begin
        read_active[slot] <= 1'b0;
        read_delay[slot] <= 0;
        read_beat[slot] <= '0;
      end
    end else begin
      for (int slot = 0; slot < 2; slot++)
        if (read_active[slot] && read_delay[slot] > 0) read_delay[slot] <= read_delay[slot] - 1;

      if (m_axi_arvalid && m_axi_arready) begin
        read_active[m_axi_arid[0]] <= 1'b1;
        read_addr[m_axi_arid[0]] <= m_axi_araddr;
        read_beat[m_axi_arid[0]] <= '0;
        read_delay[m_axi_arid[0]] <= configured_delay[m_axi_arid[0]];
        ar_count++;
      end

      if (m_axi_rvalid && m_axi_rready) begin
        if (m_axi_rlast) begin
          read_active[m_axi_rid[0]] <= 1'b0;
          read_beat[m_axi_rid[0]] <= '0;
        end else begin
          read_beat[m_axi_rid[0]] <= read_beat[m_axi_rid[0]] + 1'b1;
        end
        m_axi_rvalid <= 1'b0;
      end

      if (!m_axi_rvalid) begin
        int selected;
        selected = -1;
        if (read_active[1] && read_delay[1] == 0) selected = 1;
        else if (read_active[0] && read_delay[0] == 0) selected = 0;
        if (selected >= 0) begin
          int base_word;
          base_word = read_addr[selected] >> 2;
          m_axi_rvalid <= 1'b1;
          m_axi_rid <= 2'(selected);
          m_axi_rdata <= {backing_mem[base_word + read_beat[selected]*2 + 1],
                           backing_mem[base_word + read_beat[selected]*2]};
          m_axi_rresp <= inject_read_error && read_addr[selected] == inject_read_line ? 2'b10 : 2'b00;
          m_axi_rlast <= read_beat[selected] == 2'd3;
        end
      end

      if (m_axi_awvalid && m_axi_awready) begin
        write_active <= 1'b1;
        write_addr <= m_axi_awaddr;
        write_id <= m_axi_awid;
        write_beat <= '0;
        aw_count++;
      end
      if (m_axi_wvalid && m_axi_wready) begin
        write_buffer[write_beat] <= m_axi_wdata;
        if (m_axi_wlast) begin
          write_active <= 1'b0;
          pending_b <= 1'b1;
          pending_b_id <= write_id;
          pending_b_resp <= inject_write_error ? 2'b10 : 2'b00;
          write_beat <= '0;
        end else begin
          write_beat <= write_beat + 1'b1;
        end
      end
      if (!m_axi_bvalid && pending_b) begin
        m_axi_bvalid <= 1'b1;
        m_axi_bid <= pending_b_id;
        m_axi_bresp <= pending_b_resp;
        pending_b <= 1'b0;
      end
      if (m_axi_bvalid && m_axi_bready) begin
        if (m_axi_bresp == 2'b00) begin
          int base_word;
          base_word = write_addr >> 2;
          for (int beat = 0; beat < 4; beat++) begin
            backing_mem[base_word + beat*2] <= write_buffer[beat][31:0];
            backing_mem[base_word + beat*2 + 1] <= write_buffer[beat][63:32];
          end
        end
        m_axi_bvalid <= 1'b0;
      end
    end
  end

  assign m_axi_arready = !force_ar_stall && !read_active[m_axi_arid[0]];
  assign m_axi_awready = !force_aw_stall && !write_active && !pending_b && !m_axi_bvalid;
  assign m_axi_wready = !force_w_stall && write_active;

  always_ff @(posedge clk) begin
    cycles++;
    if (mon_mshr_occupancy > max_mshrs) max_mshrs = mon_mshr_occupancy;
    if (rst_n && cpu_rsp_valid && cpu_rsp_ready) begin
      check(expected_valid[cpu_rsp_id], $sformatf("unexpected response id %0d", cpu_rsp_id));
      if (expected_valid[cpu_rsp_id]) begin
        check(cpu_rsp_error == expected_error[cpu_rsp_id],
              $sformatf("error mismatch id %0d", cpu_rsp_id));
        if (!expected_error[cpu_rsp_id])
          check(cpu_rsp_rdata == expected_data[cpu_rsp_id],
                $sformatf("data mismatch id %0d expected %08x got %08x",
                          cpu_rsp_id, expected_data[cpu_rsp_id], cpu_rsp_rdata));
      end
      response_order[response_count] = cpu_rsp_id;
      response_seen[cpu_rsp_id] = 1'b1;
      expected_valid[cpu_rsp_id] = 1'b0;
      response_count++;
    end
  end

  task automatic test_dual_miss_reorder;
    configured_delay[0] = 18;
    configured_delay[1] = 1;
    issue(32'h0000_0100, 0, 0, 0, 8'd1, 0);
    issue(32'h0000_0220, 0, 0, 0, 8'd2, 0);
    wait_all();
    check(max_mshrs == 2, "two MSHRs became occupied");
    check(response_order[0] == 2, "second refill completed before first");
  endtask

  task automatic test_hit_under_miss;
    configured_delay[0] = 1;
    configured_delay[1] = 1;
    issue(32'h0000_0300, 0, 0, 0, 8'd10, 0);
    wait_id(10);
    configured_delay[0] = 20;
    configured_delay[1] = 20;
    issue(32'h0000_0440, 0, 0, 0, 8'd11, 0);
    issue(32'h0000_0300, 0, 0, 0, 8'd12, 0);
    wait_all();
    check(response_order[1] == 12, "hit retired before outstanding miss");
    check(mon_hit_under_miss > 0, "hit-under-miss event counted");
  endtask

  task automatic test_same_line_merge;
    int ar_before;
    configured_delay[0] = 12;
    configured_delay[1] = 12;
    ar_before = ar_count;
    issue(32'h0000_0500, 0, 0, 0, 8'd20, 0);
    issue(32'h0000_0504, 0, 0, 0, 8'd21, 0);
    wait_all();
    check(ar_count - ar_before == 1, "merged requests used one refill");
    check(mon_merged == 1, "merge event counted");
  endtask

  task automatic prepare_dirty_victim;
    issue(32'h0000_0600, 0, 0, 0, 8'd30, 0); wait_id(30);
    issue(32'h0000_0800, 0, 0, 0, 8'd31, 0); wait_id(31);
    issue(32'h0000_0600, 1, 32'hdead_beef, 4'hf, 8'd32, 0); wait_id(32);
    issue(32'h0000_0800, 0, 0, 0, 8'd33, 0); wait_id(33);
  endtask

  task automatic test_dirty_eviction;
    prepare_dirty_victim();
    issue(32'h0000_0a00, 0, 0, 0, 8'd34, 0);
    wait_all();
    check(mon_writebacks == 1, "dirty eviction issued one writeback");
    check(backing_mem[32'h600 >> 2] == 32'hdead_beef, "writeback updated backing memory");
  endtask

  task automatic test_refill_error;
    inject_read_line = 32'h0000_0c00;
    inject_read_error = 1'b1;
    issue(32'h0000_0c00, 0, 0, 0, 8'd40, 1);
    wait_id(40);
    inject_read_error = 1'b0;
    issue(32'h0000_0c00, 0, 0, 0, 8'd41, 0);
    wait_all();
    check(ar_count == 2, "failed refill did not install a cache line");
  endtask

  task automatic test_writeback_error_preserve;
    prepare_dirty_victim();
    inject_write_error = 1'b1;
    issue(32'h0000_0a00, 0, 0, 0, 8'd44, 1);
    wait_id(44);
    inject_write_error = 1'b0;
    issue(32'h0000_0600, 0, 0, 0, 8'd45, 0);
    wait_all();
    check(expected_data[45] == 32'hdead_beef, "golden dirty value retained");
    check(mon_writebacks == 1, "failed writeback was observed");
  endtask

  task automatic test_response_backpressure;
    configured_delay[0] = 1;
    configured_delay[1] = 1;
    cpu_rsp_ready = 1'b0;
    issue(32'h0000_0e00, 0, 0, 0, 8'd50, 0);
    issue(32'h0000_1020, 0, 0, 0, 8'd51, 0);
    repeat (30) @(posedge clk);
    check(cpu_rsp_valid, "response held while CPU applied backpressure");
    cpu_rsp_ready = 1'b1;
    wait_all();
  endtask

  task automatic test_reset_outstanding;
    configured_delay[0] = 30;
    configured_delay[1] = 30;
    issue(32'h0000_1200, 0, 0, 0, 8'd60, 0);
    repeat (4) @(posedge clk);
    reset_dut(1'b1);
    configured_delay[0] = 1;
    configured_delay[1] = 1;
    issue(32'h0000_1200, 0, 0, 0, 8'd61, 0);
    wait_all();
    check(response_count == 1, "reset-aborted miss produced no ghost response");
  endtask

  task automatic test_random;
    configured_delay[0] = 3;
    configured_delay[1] = 7;
    for (int op = 0; op < 100; op++) begin
      logic [31:0] addr;
      logic write;
      addr = 32'((($urandom_range(0, 63) * 32) + ($urandom_range(0, 7) * 4)));
      write = $urandom_range(0, 99) < 35;
      issue(addr, write, 32'h5a00_0000 ^ op, write ? 4'hf : 4'h0, 8'(80 + op), 0);
      if ((op % 8) == 7) begin
        while (response_count + 2 < request_count) @(posedge clk);
      end
    end
    wait_all();
    check(max_mshrs == 2, "random traffic exercised both MSHRs");
  endtask

  task automatic test_performance_serial;
    configured_delay[0] = 10;
    configured_delay[1] = 10;
    for (int op = 0; op < 32; op++) begin
      logic [31:0] addr;
      logic [7:0] id;
      addr = 32'(((op % 16) * 32) + ((op / 16) * 32'h0000_0200));
      id = 8'(120 + op);
      issue(addr, 0, 0, 0, id, 0);
      wait_id(id);
    end
    wait_all();
  endtask

  task automatic test_performance_windowed;
    configured_delay[0] = 10;
    configured_delay[1] = 10;
    for (int op = 0; op < 32; op++) begin
      logic [31:0] addr;
      addr = 32'(((op % 16) * 32) + ((op / 16) * 32'h0000_0200));
      issue(addr, 0, 0, 0, 8'(120 + op), 0);
    end
    wait_all();
    check(max_mshrs == 2, "windowed workload used both MSHRs");
  endtask

  initial begin
    cycles = 0;
    checks = 0;
    failures = 0;
    ar_count = 0;
    aw_count = 0;
    max_mshrs = 0;
    cpu_req_valid = 1'b0;
    cpu_req_addr = '0;
    cpu_req_write = 1'b0;
    cpu_req_wdata = '0;
    cpu_req_wstrb = '0;
    cpu_req_id = '0;
    cpu_rsp_ready = 1'b1;
    inject_read_error = 1'b0;
    inject_read_line = '0;
    inject_write_error = 1'b0;
    force_ar_stall = 1'b0;
    force_aw_stall = 1'b0;
    force_w_stall = 1'b0;
    configured_delay[0] = 1;
    configured_delay[1] = 1;
    for (int word = 0; word < MEM_WORDS; word++) begin
      backing_mem[word] = 32'h1000_0000 ^ word;
      golden_mem[word] = 32'h1000_0000 ^ word;
    end
    clear_scoreboard();
    if (!$value$plusargs("TEST=%s", test_name)) test_name = "dual_miss_reorder";
    reset_dut(1'b1);

    case (test_name)
      "dual_miss_reorder": test_dual_miss_reorder();
      "hit_under_miss": test_hit_under_miss();
      "same_line_merge": test_same_line_merge();
      "dirty_eviction": test_dirty_eviction();
      "refill_error": test_refill_error();
      "writeback_error_preserve": test_writeback_error_preserve();
      "response_backpressure": test_response_backpressure();
      "reset_outstanding": test_reset_outstanding();
      "random": test_random();
      "performance_serial": test_performance_serial();
      "performance_windowed": test_performance_windowed();
      default: begin failures++; $display("Unknown test %s", test_name); end
    endcase

    repeat (5) @(posedge clk);
    $display("NB_CACHE_RESULT|test=%s|status=%s|checks=%0d|requests=%0d|responses=%0d|max_mshrs=%0d|merged=%0d|hit_under_miss=%0d|writebacks=%0d|cycles=%0d",
             test_name, failures == 0 ? "PASS" : "FAIL", checks, request_count,
             response_count, max_mshrs, mon_merged, mon_hit_under_miss, mon_writebacks, cycles);
    if (failures != 0) $fatal(1, "non-blocking cache test failed");
    $finish;
  end

endmodule
