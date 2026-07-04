`timescale 1ns/1ps

module tb_l1_dcache;
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  logic cpu_req_valid, cpu_req_ready, cpu_req_write;
  logic [31:0] cpu_req_addr, cpu_req_wdata;
  logic [3:0] cpu_req_wstrb;
  logic [2:0] cpu_req_size;
  logic [7:0] cpu_req_id;
  logic cpu_rsp_valid, cpu_rsp_ready, cpu_rsp_error;
  logic [31:0] cpu_rsp_rdata;
  logic [7:0] cpu_rsp_id;
  logic maint_valid, maint_ready, maint_busy, maint_done, maint_error;
  logic [1:0] maint_cmd;

  logic [31:0] m_axi_awaddr, m_axi_araddr;
  logic [7:0] m_axi_awlen, m_axi_arlen;
  logic [2:0] m_axi_awsize, m_axi_arsize;
  logic [1:0] m_axi_awburst, m_axi_arburst;
  logic m_axi_awvalid, m_axi_awready;
  logic [63:0] m_axi_wdata;
  logic [7:0] m_axi_wstrb;
  logic m_axi_wlast, m_axi_wvalid, m_axi_wready;
  logic [1:0] m_axi_bresp;
  logic m_axi_bvalid, m_axi_bready;
  logic m_axi_arvalid, m_axi_arready;
  logic [63:0] m_axi_rdata;
  logic [1:0] m_axi_rresp;
  logic m_axi_rlast, m_axi_rvalid, m_axi_rready;
  logic [4:0] mon_state;
  logic mon_hit, mon_miss, mon_evict;
  logic [1:0] mon_refill_beat, mon_writeback_beat;

  l1_dcache_top dut (.*);

  logic [31:0] memory [0:65535];
  logic wr_active, rd_active;
  logic [31:0] wr_addr, rd_addr;
  logic [2:0] wr_beat, rd_beat;
  logic inject_read_error, inject_write_error;
  integer stall_mod = 0;
  integer aw_stall_budget = 0;
  integer w_stall_budget = 0;
  integer ar_stall_budget = 0;
  integer b_delay_cfg = 0;
  integer b_delay_count = 0;
  logic [1:0] pending_bresp;
  integer cycle_count = 0;
  integer hit_count = 0;
  integer miss_count = 0;
  integer eviction_count = 0;
  integer request_count = 0;
  integer response_count = 0;
  integer error_count = 0;
  integer failures = 0;
  integer next_id = 1;
  string test_name;

  wire allow_ready = stall_mod == 0 || (cycle_count % stall_mod) != 0;
  assign m_axi_awready = !wr_active && !m_axi_bvalid && allow_ready && aw_stall_budget == 0;
  assign m_axi_wready = wr_active && allow_ready && w_stall_budget == 0;
  assign m_axi_arready = !rd_active && allow_ready && ar_stall_budget == 0;

  always_ff @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    if (mon_hit) hit_count <= hit_count + 1;
    if (mon_miss) miss_count <= miss_count + 1;
    if (mon_evict) eviction_count <= eviction_count + 1;

    if (!rst_n) begin
      wr_active <= 0;
      rd_active <= 0;
      m_axi_bvalid <= 0;
      m_axi_bresp <= 0;
      m_axi_rvalid <= 0;
      m_axi_rdata <= 0;
      m_axi_rresp <= 0;
      m_axi_rlast <= 0;
      wr_beat <= 0;
      rd_beat <= 0;
      aw_stall_budget <= 0;
      w_stall_budget <= 0;
      ar_stall_budget <= 0;
      b_delay_count <= 0;
      pending_bresp <= 0;
    end else begin
      if (m_axi_awvalid && aw_stall_budget > 0) aw_stall_budget <= aw_stall_budget - 1;
      if (m_axi_wvalid && w_stall_budget > 0) w_stall_budget <= w_stall_budget - 1;
      if (m_axi_arvalid && ar_stall_budget > 0) ar_stall_budget <= ar_stall_budget - 1;
      if (b_delay_count > 0) begin
        b_delay_count <= b_delay_count - 1;
        if (b_delay_count == 1) begin
          m_axi_bvalid <= 1;
          m_axi_bresp <= pending_bresp;
        end
      end
      if (m_axi_awvalid && m_axi_awready) begin
        wr_active <= 1;
        wr_addr <= m_axi_awaddr;
        wr_beat <= 0;
        if (m_axi_awlen != 3 || m_axi_awsize != 3 || m_axi_awburst != 1) begin
          $error("Invalid AXI write burst");
          failures <= failures + 1;
        end
      end

      if (m_axi_wvalid && m_axi_wready) begin
        for (int byte_idx = 0; byte_idx < 8; byte_idx++) begin
          if (m_axi_wstrb[byte_idx])
            memory[(wr_addr >> 2) + wr_beat*2 + int'(byte_idx >= 4)]
              [(byte_idx % 4)*8 +: 8] <= m_axi_wdata[byte_idx*8 +: 8];
        end
        if (m_axi_wlast) begin
          if (wr_beat != 3) begin
            $error("WLAST at beat %0d", wr_beat);
            failures <= failures + 1;
          end
          wr_active <= 0;
          pending_bresp <= inject_write_error ? 2'b10 : 2'b00;
          if (b_delay_cfg == 0) begin
            m_axi_bvalid <= 1;
            m_axi_bresp <= inject_write_error ? 2'b10 : 2'b00;
          end else begin
            b_delay_count <= b_delay_cfg;
          end
        end else begin
          wr_beat <= wr_beat + 1;
        end
      end
      if (m_axi_bvalid && m_axi_bready) m_axi_bvalid <= 0;

      if (m_axi_arvalid && m_axi_arready) begin
        rd_active <= 1;
        rd_addr <= m_axi_araddr;
        rd_beat <= 0;
        if (m_axi_arlen != 3 || m_axi_arsize != 3 || m_axi_arburst != 1) begin
          $error("Invalid AXI read burst");
          failures <= failures + 1;
        end
      end

      if (rd_active && !m_axi_rvalid && allow_ready) begin
        m_axi_rdata <= {memory[(rd_addr >> 2) + rd_beat*2 + 1],
                        memory[(rd_addr >> 2) + rd_beat*2]};
        m_axi_rresp <= inject_read_error && rd_beat == 2 ? 2'b10 : 2'b00;
        m_axi_rlast <= rd_beat == 3;
        m_axi_rvalid <= 1;
      end
      if (m_axi_rvalid && m_axi_rready) begin
        m_axi_rvalid <= 0;
        if (m_axi_rlast) begin
          rd_active <= 0;
          m_axi_rlast <= 0;
        end else begin
          rd_beat <= rd_beat + 1;
        end
      end
    end
  end

  task automatic reset_dut;
    cpu_req_valid = 0;
    cpu_rsp_ready = 1;
    maint_valid = 0;
    maint_cmd = 0;
    inject_read_error = 0;
    inject_write_error = 0;
    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);
  endtask

  task automatic cpu_access(
    input bit write,
    input logic [31:0] addr,
    input logic [31:0] wdata,
    input logic [3:0] wstrb,
    input logic [2:0] size,
    output logic [31:0] rdata,
    output bit error
  );
    logic [7:0] issued_id;
    issued_id = next_id[7:0];
    next_id++;
    @(negedge clk);
    cpu_req_valid = 1;
    cpu_req_addr = addr;
    cpu_req_write = write;
    cpu_req_wdata = wdata;
    cpu_req_wstrb = wstrb;
    cpu_req_size = size;
    cpu_req_id = issued_id;
    do @(posedge clk); while (!cpu_req_ready);
    request_count++;
    @(negedge clk);
    cpu_req_valid = 0;
    do @(posedge clk); while (!cpu_rsp_valid);
    response_count++;
    rdata = cpu_rsp_rdata;
    error = cpu_rsp_error;
    if (error) error_count++;
    if (cpu_rsp_id != issued_id) begin
      $error("Response ID mismatch expected=%0d actual=%0d", issued_id, cpu_rsp_id);
      failures++;
    end
  endtask

  task automatic expect_read(input logic [31:0] addr, input logic [31:0] expected);
    logic [31:0] actual;
    bit error;
    cpu_access(0, addr, 0, 0, 2, actual, error);
    if (error || actual !== expected) begin
      $error("Read mismatch addr=%08x expected=%08x actual=%08x error=%0d",
             addr, expected, actual, error);
      failures++;
    end
  endtask

  task automatic run_smoke;
    logic [31:0] ignored;
    bit error;
    expect_read(32'h0000_1000, memory[32'h1000 >> 2]);
    expect_read(32'h0000_1000, memory[32'h1000 >> 2]);
    cpu_access(1, 32'h0000_1000, 32'hdead_beef, 4'hf, 2, ignored, error);
    if (error) failures++;
    expect_read(32'h0000_1000, 32'hdead_beef);
  endtask

  task automatic run_dirty_evict;
    logic [31:0] ignored;
    bit error;
    cpu_access(1, 32'h0000_1000, 32'hcafe_0001, 4'hf, 2, ignored, error);
    expect_read(32'h0000_1800, memory[32'h1800 >> 2]);
    expect_read(32'h0000_2000, memory[32'h2000 >> 2]);
    if (memory[32'h1000 >> 2] !== 32'hcafe_0001) begin
      $error("Dirty victim was not written back");
      failures++;
    end
  endtask

  task automatic run_backpressure;
    if (stall_mod == 0) stall_mod = 3;
    run_dirty_evict();
    stall_mod = 0;
  endtask

  task automatic run_read_error;
    logic [31:0] actual;
    bit error;
    inject_read_error = 1;
    cpu_access(0, 32'h0000_3400, 0, 0, 2, actual, error);
    if (!error) begin $error("Read error was not propagated"); failures++; end
    inject_read_error = 0;
    expect_read(32'h0000_3400, memory[32'h3400 >> 2]);
  endtask

  task automatic run_byte_strobes;
    logic [31:0] ignored;
    logic [31:0] initial_word;
    logic [31:0] expected;
    bit error;
    initial_word = memory[32'h3000 >> 2];
    expect_read(32'h0000_3000, initial_word);
    cpu_access(1, 32'h0000_3000, 32'haabb_ccdd, 4'b0101, 2, ignored, error);
    expected = {initial_word[31:24], 8'hbb, initial_word[15:8], 8'hdd};
    expect_read(32'h0000_3000, expected);
  endtask

  task automatic run_misaligned;
    logic [31:0] actual;
    bit error;
    cpu_access(0, 32'h0000_1001, 0, 0, 2, actual, error);
    if (!error) begin $error("Misaligned access was not rejected"); failures++; end
    expect_read(32'h0000_1000, memory[32'h1000 >> 2]);
  endtask

  task automatic run_write_error;
    logic [31:0] ignored;
    bit error;
    cpu_access(1, 32'h0000_1000, 32'hfeed_0001, 4'hf, 2, ignored, error);
    expect_read(32'h0000_1800, memory[32'h1800 >> 2]);
    inject_write_error = 1;
    cpu_access(0, 32'h0000_2000, 0, 0, 2, ignored, error);
    if (!error) begin $error("Writeback error was not propagated"); failures++; end
    inject_write_error = 0;
    expect_read(32'h0000_1000, 32'hfeed_0001);
  endtask

  task automatic run_maintenance;
    logic [31:0] ignored;
    bit error;
    cpu_access(1, 32'h0000_2800, 32'h1234_5678, 4'hf, 2, ignored, error);
    @(negedge clk);
    maint_valid = 1;
    maint_cmd = 2'd2;
    do @(posedge clk); while (!maint_ready);
    @(negedge clk);
    maint_valid = 0;
    do @(posedge clk); while (!maint_done);
    if (maint_error || memory[32'h2800 >> 2] !== 32'h1234_5678) begin
      $error("Flush/invalidate maintenance failed");
      failures++;
    end
    expect_read(32'h0000_2800, 32'h1234_5678);
  endtask

  task automatic issue_maintenance(input logic [1:0] command);
    @(negedge clk);
    maint_valid = 1;
    maint_cmd = command;
    do @(posedge clk); while (!maint_ready);
    @(negedge clk);
    maint_valid = 0;
    do @(posedge clk); while (!maint_done);
    if (maint_error) begin $error("Maintenance command %0d failed", command); failures++; end
  endtask

  task automatic run_flush_only;
    logic [31:0] ignored;
    bit error;
    cpu_access(1, 32'h0000_2c00, 32'h9876_5432, 4'hf, 2, ignored, error);
    issue_maintenance(2'd0);
    if (memory[32'h2c00 >> 2] !== 32'h9876_5432) begin
      $error("Flush did not update backing memory"); failures++;
    end
    expect_read(32'h0000_2c00, 32'h9876_5432);
  endtask

  task automatic run_invalidate_only;
    int misses_before;
    expect_read(32'h0000_2400, memory[32'h2400 >> 2]);
    issue_maintenance(2'd1);
    misses_before = miss_count;
    expect_read(32'h0000_2400, memory[32'h2400 >> 2]);
    if (miss_count <= misses_before) begin $error("Invalidate did not force a miss"); failures++; end
  endtask

  task automatic run_response_backpressure;
    logic [31:0] held_data;
    logic [7:0] held_id;
    @(negedge clk);
    cpu_rsp_ready = 0;
    cpu_req_valid = 1;
    cpu_req_addr = 32'h0000_1400;
    cpu_req_write = 0;
    cpu_req_wdata = 0;
    cpu_req_wstrb = 0;
    cpu_req_size = 2;
    cpu_req_id = next_id[7:0];
    next_id++;
    do @(posedge clk); while (!cpu_req_ready);
    request_count++;
    @(negedge clk); cpu_req_valid = 0;
    do @(posedge clk); while (!cpu_rsp_valid);
    held_data = cpu_rsp_rdata;
    held_id = cpu_rsp_id;
    repeat (5) begin
      @(posedge clk);
      if (!cpu_rsp_valid || cpu_rsp_rdata !== held_data || cpu_rsp_id !== held_id) begin
        $error("CPU response changed under backpressure"); failures++;
      end
    end
    @(negedge clk); cpu_rsp_ready = 1;
    @(posedge clk); response_count++;
  endtask

  task automatic run_reset_mid_refill;
    @(negedge clk);
    cpu_req_valid = 1;
    cpu_req_addr = 32'h0000_3800;
    cpu_req_write = 0;
    cpu_req_wdata = 0;
    cpu_req_wstrb = 0;
    cpu_req_size = 2;
    cpu_req_id = next_id[7:0];
    next_id++;
    do @(posedge clk); while (!cpu_req_ready);
    @(negedge clk); cpu_req_valid = 0;
    do @(posedge clk); while (mon_state != 5'd6);
    @(negedge clk); rst_n = 0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1;
    repeat (3) @(posedge clk);
    if (cpu_rsp_valid) begin $error("Reset created a phantom response"); failures++; end
    expect_read(32'h0000_3800, memory[32'h3800 >> 2]);
  endtask

  task automatic run_axi_channel_waits;
    ar_stall_budget = 3;
    expect_read(32'h0000_3000, memory[32'h3000 >> 2]);
    aw_stall_budget = 3;
    w_stall_budget = 3;
    b_delay_cfg = 3;
    run_dirty_evict();
    b_delay_cfg = 0;
  endtask

  task automatic run_maintenance_error;
    logic [31:0] ignored;
    bit error;
    cpu_access(1, 32'h0000_2c00, 32'hface_1234, 4'hf, 2, ignored, error);
    inject_write_error = 1;
    @(negedge clk); maint_valid = 1; maint_cmd = 2'd0;
    do @(posedge clk); while (!maint_ready);
    @(negedge clk); maint_valid = 0;
    do @(posedge clk); while (!maint_done);
    if (!maint_error) begin $error("Maintenance writeback error was not reported"); failures++; end
    inject_write_error = 0;
  endtask

  task automatic run_maintenance_final_dirty;
    logic [31:0] ignored;
    bit error;
    cpu_access(1, 32'h0000_17e0, 32'h1111_aaaa, 4'hf, 2, ignored, error);
    cpu_access(1, 32'h0000_1fe0, 32'h2222_bbbb, 4'hf, 2, ignored, error);
    issue_maintenance(2'd0);
    if (memory[32'h17e0 >> 2] !== 32'h1111_aaaa ||
        memory[32'h1fe0 >> 2] !== 32'h2222_bbbb) begin
      $error("Final-set dirty maintenance writeback failed"); failures++;
    end
  endtask

  task automatic run_maintenance_channel_waits;
    logic [31:0] ignored;
    bit error;
    cpu_access(1, 32'h0000_1200, 32'ha5a5_1234, 4'hf, 2, ignored, error);
    cpu_access(1, 32'h0000_1a00, 32'h5a5a_5678, 4'hf, 2, ignored, error);
    aw_stall_budget = 3;
    w_stall_budget = 3;
    b_delay_cfg = 3;
    issue_maintenance(2'd0);
    b_delay_cfg = 0;
    if (memory[32'h1200 >> 2] !== 32'ha5a5_1234 ||
        memory[32'h1a00 >> 2] !== 32'h5a5a_5678) begin
      $error("Maintenance AXI wait-state writeback failed first=%08x second=%08x",
             memory[32'h1200 >> 2], memory[32'h1a00 >> 2]); failures++;
    end
  endtask

  task automatic run_random;
    logic [31:0] model [0:255];
    logic [31:0] actual, data;
    logic [31:0] addr;
    bit error;
    for (int i = 0; i < 256; i++) model[i] = memory[(32'h4000 >> 2) + i];
    for (int n = 0; n < 100; n++) begin
      int index = $urandom_range(0, 255);
      addr = 32'h4000 + index*4;
      if (bit'($urandom_range(0, 1))) begin
        data = $urandom;
        cpu_access(1, addr, data, 4'hf, 2, actual, error);
        model[index] = data;
      end else begin
        cpu_access(0, addr, 0, 0, 2, actual, error);
        if (error || actual !== model[index]) begin
          $error("Random mismatch index=%0d expected=%08x actual=%08x", index, model[index], actual);
          failures++;
        end
      end
    end
  endtask

  initial begin
    if (!$value$plusargs("TEST=%s", test_name)) test_name = "smoke";
    void'($value$plusargs("STALL_MOD=%d", stall_mod));
    for (int i = 0; i < 65536; i++) memory[i] = 32'h1000_0000 ^ i;
    reset_dut();
    case (test_name)
      "smoke": run_smoke();
      "dirty_evict": run_dirty_evict();
      "backpressure": run_backpressure();
      "read_error": run_read_error();
      "byte_strobes": run_byte_strobes();
      "misaligned": run_misaligned();
      "write_error": run_write_error();
      "maintenance": run_maintenance();
      "flush_only": run_flush_only();
      "invalidate_only": run_invalidate_only();
      "response_backpressure": run_response_backpressure();
      "reset_mid_refill": run_reset_mid_refill();
      "axi_channel_waits": run_axi_channel_waits();
      "maintenance_error": run_maintenance_error();
      "maintenance_final_dirty": run_maintenance_final_dirty();
      "maintenance_channel_waits": run_maintenance_channel_waits();
      "random": run_random();
      default: begin $error("Unknown TEST=%s", test_name); failures++; end
    endcase
    repeat (5) @(posedge clk);
    if (request_count != response_count) begin
      $error("Request/response count mismatch %0d/%0d", request_count, response_count);
      failures++;
    end
    $display("CACHE_RESULT|test=%s|status=%s|requests=%0d|responses=%0d|hits=%0d|misses=%0d|evictions=%0d|errors=%0d|cycles=%0d",
             test_name, failures == 0 ? "PASS" : "FAIL", request_count, response_count,
             hit_count, miss_count, eviction_count, error_count, cycle_count);
    if (failures != 0) $fatal(1, "%0d failures", failures);
    $finish;
  end

  initial begin
    repeat (20000) @(posedge clk);
    $fatal(1, "Timeout in %s", test_name);
  end
endmodule
