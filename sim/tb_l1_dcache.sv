`timescale 1ns/1ps

module tb_l1_dcache #(
  parameter int CACHE_SETS = 64,
  parameter int CACHE_WAYS = 2,
  parameter bit CACHE_SECDED_ENABLE = 1'b0
);
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

  l1_dcache_top #(
    .SETS(CACHE_SETS),
    .WAYS(CACHE_WAYS),
    .PARITY_ENABLE(!CACHE_SECDED_ENABLE),
    .SECDED_ENABLE(CACHE_SECDED_ENABLE)
  ) dut (.*);

  logic [31:0] memory [0:65535];
  logic memory_touched [0:65535];
  logic wr_active, rd_active;
  logic [31:0] wr_addr, rd_addr;
  logic [2:0] wr_beat, rd_beat;
  logic inject_read_error, inject_write_error;
  integer read_error_beat = 2;
  integer stall_mod = 0;
  integer bp_percent = 0;
  integer random_operations = 100;
  integer random_read_percent = 50;
  integer random_conflict_percent = 0;
  integer random_error_percent = 0;
  integer random_reset_operation = -1;
  integer random_seed_cfg = 1;
  integer random_addr_base = 'h4000;
  integer random_addr_span = 'h4000;
  string random_reset_phase = "idle";
  string random_strobe_profile = "full";
  string random_addr_profile = "uniform";
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
  integer axi_aw_handshakes = 0;
  integer axi_ar_handshakes = 0;
  integer ecc_corrected_count = 0;
  integer ecc_uncorrectable_count = 0;
  integer ecc_scrub_count = 0;
  integer failures = 0;
  integer next_id = 1;
  string test_name;
  string wave_file;
  bit model_final_flush = 0;

  initial begin
    if ($value$plusargs("WAVE_FILE=%s", wave_file)) begin
      $dumpfile(wave_file);
      $dumpvars(0, tb_l1_dcache);
    end
  end

  integer axi_stall_cycles = 0;
  integer axi_valid_cycles = 0;
  wire percent_ready = bp_percent == 0 ||
                       (((cycle_count * 37 + random_seed_cfg) % 100) >= bp_percent);
  wire allow_ready = (stall_mod == 0 || (cycle_count % stall_mod) != 0) && percent_ready;
  assign m_axi_awready = !wr_active && !m_axi_bvalid && allow_ready && aw_stall_budget == 0;
  assign m_axi_wready = wr_active && allow_ready && w_stall_budget == 0;
  assign m_axi_arready = !rd_active && allow_ready && ar_stall_budget == 0;

  always_ff @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    if (mon_hit) hit_count <= hit_count + 1;
    if (mon_miss) miss_count <= miss_count + 1;
    if (mon_evict) eviction_count <= eviction_count + 1;
    if (m_axi_awvalid || m_axi_wvalid || m_axi_arvalid || m_axi_rvalid)
      axi_valid_cycles <= axi_valid_cycles + 1;
    if (m_axi_awvalid && m_axi_awready) axi_aw_handshakes <= axi_aw_handshakes + 1;
    if (m_axi_arvalid && m_axi_arready) axi_ar_handshakes <= axi_ar_handshakes + 1;
    if (dut.ecc_corrected_pulse) ecc_corrected_count <= ecc_corrected_count + 1;
    if (dut.ecc_uncorrectable_pulse) ecc_uncorrectable_count <= ecc_uncorrectable_count + 1;
    if (dut.ecc_scrub_write) ecc_scrub_count <= ecc_scrub_count + 1;
    if ((m_axi_awvalid && !m_axi_awready) || (m_axi_wvalid && !m_axi_wready) ||
        (m_axi_arvalid && !m_axi_arready) || (m_axi_rvalid && !m_axi_rready))
      axi_stall_cycles <= axi_stall_cycles + 1;

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
        memory_touched[(wr_addr >> 2) + wr_beat*2] <= 1;
        memory_touched[(wr_addr >> 2) + wr_beat*2 + 1] <= 1;
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
        m_axi_rresp <= inject_read_error && rd_beat == read_error_beat[2:0] ? 2'b10 : 2'b00;
        m_axi_rlast <= rd_beat == 3;
        m_axi_rvalid <= 1;
      end
      if (m_axi_rvalid && m_axi_rready) begin
        memory_touched[(rd_addr >> 2) + rd_beat*2] <= 1;
        memory_touched[(rd_addr >> 2) + rd_beat*2 + 1] <= 1;
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
    read_error_beat = 2;
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

  task automatic run_read_miss;
    int ar_before = axi_ar_handshakes;
    int aw_before = axi_aw_handshakes;
    int miss_before = miss_count;
    expect_read(32'h0000_4000, memory[32'h4000 >> 2]);
    if (axi_ar_handshakes != ar_before + 1 || axi_aw_handshakes != aw_before ||
        miss_count <= miss_before) begin
      $error("Read miss did not issue exactly one refill burst");
      failures++;
    end
  endtask

  task automatic run_read_hit;
    int ar_before;
    int aw_before;
    int hit_before;
    expect_read(32'h0000_4400, memory[32'h4400 >> 2]);
    ar_before = axi_ar_handshakes;
    aw_before = axi_aw_handshakes;
    hit_before = hit_count;
    expect_read(32'h0000_4400, memory[32'h4400 >> 2]);
    if (axi_ar_handshakes != ar_before || axi_aw_handshakes != aw_before ||
        hit_count <= hit_before) begin
      $error("Read hit unexpectedly accessed AXI");
      failures++;
    end
  endtask

  task automatic run_write_miss;
    logic [31:0] ignored;
    bit error;
    int ar_before = axi_ar_handshakes;
    int aw_before = axi_aw_handshakes;
    int miss_before = miss_count;
    cpu_access(1, 32'h0000_4800, 32'hc001_cafe, 4'hf, 2, ignored, error);
    if (error || axi_ar_handshakes != ar_before + 1 ||
        axi_aw_handshakes != aw_before || miss_count <= miss_before) begin
      $error("Write miss did not allocate through one refill burst");
      failures++;
    end
    expect_read(32'h0000_4800, 32'hc001_cafe);
  endtask

  task automatic run_write_hit;
    logic [31:0] ignored;
    bit error;
    int ar_before;
    int aw_before;
    int hit_before;
    expect_read(32'h0000_4c00, memory[32'h4c00 >> 2]);
    ar_before = axi_ar_handshakes;
    aw_before = axi_aw_handshakes;
    hit_before = hit_count;
    cpu_access(1, 32'h0000_4c00, 32'h51a7_0bad, 4'hf, 2, ignored, error);
    expect_read(32'h0000_4c00, 32'h51a7_0bad);
    if (error || axi_ar_handshakes != ar_before || axi_aw_handshakes != aw_before ||
        hit_count < hit_before + 2) begin
      $error("Write-hit path unexpectedly accessed AXI or failed replay");
      failures++;
    end
  endtask

  task automatic run_clean_evict;
    int ar_before;
    int aw_before;
    expect_read(32'h0000_7000, memory[32'h7000 >> 2]);
    expect_read(32'h0000_7800, memory[32'h7800 >> 2]);
    ar_before = axi_ar_handshakes;
    aw_before = axi_aw_handshakes;
    expect_read(32'h0000_8000, memory[32'h8000 >> 2]);
    if (axi_ar_handshakes != ar_before + 1 || axi_aw_handshakes != aw_before) begin
      $error("Clean eviction issued an unexpected writeback");
      failures++;
    end
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

  task automatic run_byte_strobe_lane_matrix;
    logic [31:0] ignored;
    logic [31:0] shadow [int unsigned];
    logic [31:0] bases [0:1];
    logic [31:0] addr;
    logic [31:0] data;
    logic [31:0] expected;
    logic [3:0] mask;
    bit error;
    int stride;
    int word;
    int key;

    stride = CACHE_SETS * 32;
    bases[0] = 32'h0000_e000;
    bases[1] = bases[0] + stride;
    expect_read(bases[0], memory[bases[0] >> 2]);
    expect_read(bases[1], memory[bases[1] >> 2]);

    for (int m = 0; m < 16; m++) begin
      mask = m[3:0];
      word = (m * 3) % 8;
      addr = bases[m[0]] + word*4;
      key = addr >> 2;
      if (shadow.exists(key) == 0) shadow[key] = memory[key];
      data = 32'h8100_0000 ^ (32'(m) * 32'h0102_0304) ^ addr;
      expected = shadow[key];
      for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
        if (mask[byte_idx])
          expected[byte_idx*8 +: 8] = data[byte_idx*8 +: 8];
      end
      cpu_access(1, addr, data, mask, 2, ignored, error);
      if (error) begin
        $error("Byte-strobe matrix write unexpectedly errored mask=%0h addr=%08x", mask, addr);
        failures++;
      end
      shadow[key] = expected;
      expect_read(addr, expected);
    end
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

  task automatic run_set_way_sweep_toggle;
    logic [31:0] ignored;
    logic [31:0] line0;
    logic [31:0] line1;
    logic [31:0] line2;
    bit error;
    int stride;
    int set_idx;

    stride = CACHE_SETS * 32;
    for (int n = 0; n < 8; n++) begin
      case (n)
        0: set_idx = 0;
        1: set_idx = 1;
        2: set_idx = 7;
        3: set_idx = 15;
        4: set_idx = 31;
        5: set_idx = CACHE_SETS / 2;
        6: set_idx = CACHE_SETS - 2;
        default: set_idx = CACHE_SETS - 1;
      endcase
      line0 = 32'h0000_4000 + set_idx*32;
      line1 = line0 + stride;
      line2 = line0 + 2*stride;
      expect_read(line0, memory[line0 >> 2]);
      expect_read(line1, memory[line1 >> 2]);
      cpu_access(1, line0, 32'h5a00_0000 ^ 32'(set_idx), 4'hf, 2, ignored, error);
      cpu_access(1, line1 + 4, 32'ha500_0000 ^ 32'(set_idx), 4'hf, 2, ignored, error);
      expect_read(line2, memory[line2 >> 2]);
      cpu_access(1, line2 + 8, 32'hc300_0000 ^ 32'(set_idx), 4'b0110, 2, ignored, error);
    end
    issue_maintenance(2'd1);
  endtask

  task automatic run_maintenance_boundary_sets;
    logic [31:0] ignored;
    logic [31:0] addr0;
    logic [31:0] addr1;
    logic [31:0] addr2;
    logic [31:0] orig0;
    logic [31:0] orig1;
    logic [31:0] orig2;
    logic [31:0] val0;
    logic [31:0] val1;
    logic [31:0] val2;
    logic [31:0] read_expected0;
    logic [31:0] read_expected1;
    logic [31:0] read_expected2;
    bit error;
    int mid_set;
    int final_set;
    int misses_before;

    mid_set = CACHE_SETS / 2;
    final_set = CACHE_SETS - 1;
    addr0 = 32'h0000_f000;
    addr1 = 32'h0000_f000 + mid_set*32;
    addr2 = 32'h0000_f000 + final_set*32;

    for (int command = 0; command < 3; command++) begin
      reset_between_operations();
      orig0 = memory[addr0 >> 2];
      orig1 = memory[addr1 >> 2];
      orig2 = memory[addr2 >> 2];
      val0 = 32'hba00_0000 ^ 32'(command);
      val1 = 32'hba00_1000 ^ 32'(command);
      val2 = 32'hba00_2000 ^ 32'(command);
      cpu_access(1, addr0, val0, 4'hf, 2, ignored, error);
      cpu_access(1, addr1, val1, 4'hf, 2, ignored, error);
      cpu_access(1, addr2, val2, 4'hf, 2, ignored, error);
      misses_before = miss_count;
      issue_maintenance(command[1:0]);

      if (command == 0 || command == 2) begin
        if (memory[addr0 >> 2] !== val0 || memory[addr1 >> 2] !== val1 ||
            memory[addr2 >> 2] !== val2) begin
          $error("Boundary maintenance command %0d failed final writeback", command);
          failures++;
        end
      end

      read_expected0 = (command == 1) ? orig0 : val0;
      read_expected1 = (command == 1) ? orig1 : val1;
      read_expected2 = (command == 1) ? orig2 : val2;
      expect_read(addr0, read_expected0);
      expect_read(addr1, read_expected1);
      expect_read(addr2, read_expected2);
      if ((command == 1 || command == 2) && miss_count <= misses_before) begin
        $error("Boundary invalidate command %0d did not force a later miss", command);
        failures++;
      end
    end
  endtask

  task automatic run_reset_refill_beat_matrix;
    logic [31:0] addr;
    for (int beat = 0; beat < 4; beat++) begin
      reset_between_operations();
      addr = 32'h0001_0000 + beat*32;
      @(negedge clk);
      cpu_req_valid = 1;
      cpu_req_addr = addr;
      cpu_req_write = 0;
      cpu_req_wdata = 0;
      cpu_req_wstrb = 0;
      cpu_req_size = 2;
      cpu_req_id = next_id[7:0];
      next_id++;
      do @(posedge clk); while (!cpu_req_ready);
      @(negedge clk); cpu_req_valid = 0;
      do @(posedge clk); while (!(mon_state == 5'd6 && mon_refill_beat == beat[1:0]));
      @(negedge clk); rst_n = 0;
      repeat (3) @(posedge clk);
      @(negedge clk); rst_n = 1;
      repeat (3) @(posedge clk);
      if (cpu_rsp_valid) begin
        $error("Reset during refill beat %0d created a ghost response", beat);
        failures++;
      end
      expect_read(addr, memory[addr >> 2]);
    end
  endtask

  task automatic run_reset_writeback_beat_matrix;
    logic [31:0] ignored;
    logic [31:0] line0;
    logic [31:0] line1;
    logic [31:0] line2;
    bit error;
    int stride;
    stride = CACHE_SETS * 32;
    for (int beat = 0; beat < 4; beat++) begin
      reset_between_operations();
      line0 = 32'h0001_1000 + beat*32;
      line1 = line0 + stride;
      line2 = line0 + 2*stride;
      cpu_access(1, line0, 32'hde00_1000 ^ 32'(beat), 4'hf, 2, ignored, error);
      expect_read(line1, memory[line1 >> 2]);
      @(negedge clk);
      cpu_req_valid = 1;
      cpu_req_addr = line2;
      cpu_req_write = 0;
      cpu_req_wdata = 0;
      cpu_req_wstrb = 0;
      cpu_req_size = 2;
      cpu_req_id = next_id[7:0];
      next_id++;
      do @(posedge clk); while (!cpu_req_ready);
      @(negedge clk); cpu_req_valid = 0;
      do @(posedge clk); while (!(mon_state == 5'd3 && mon_writeback_beat == beat[1:0]));
      @(negedge clk); rst_n = 0;
      repeat (3) @(posedge clk);
      @(negedge clk); rst_n = 1;
      repeat (3) @(posedge clk);
      if (cpu_rsp_valid) begin
        $error("Reset during writeback beat %0d created a ghost response", beat);
        failures++;
      end
      expect_read(line2, memory[line2 >> 2]);
    end
  endtask

  task automatic run_reset_maintenance_scan_matrix;
    logic [31:0] ignored;
    logic [31:0] addr;
    int target_sets [0:2];
    bit error;
    target_sets[0] = 0;
    target_sets[1] = CACHE_SETS / 2;
    target_sets[2] = CACHE_SETS - 1;
    for (int idx = 0; idx < 3; idx++) begin
      reset_between_operations();
      for (int fill_idx = 0; fill_idx < 3; fill_idx++) begin
        addr = 32'h0001_4000 + target_sets[fill_idx]*32;
        cpu_access(1, addr, 32'h5c00_0000 ^ 32'(idx) ^ 32'(fill_idx), 4'hf, 2,
                   ignored, error);
      end
      @(negedge clk);
      maint_valid = 1;
      maint_cmd = 2'd2;
      do @(posedge clk); while (!maint_ready);
      @(negedge clk); maint_valid = 0;
      do @(posedge clk); while (!(mon_state == 5'd10 && int'(dut.maint_set) == target_sets[idx]));
      @(negedge clk); rst_n = 0;
      repeat (3) @(posedge clk);
      @(negedge clk); rst_n = 1;
      repeat (3) @(posedge clk);
      if (maint_done || cpu_rsp_valid) begin
        $error("Reset during maintenance scan set %0d left stale done/response", target_sets[idx]);
        failures++;
      end
      expect_read(32'h0001_4000 + target_sets[idx]*32,
                  memory[(32'h0001_4000 + target_sets[idx]*32) >> 2]);
    end
  endtask

  task automatic run_axi_read_error_beat_matrix;
    logic [31:0] actual;
    bit error;
    int miss_before;
    for (int beat = 0; beat < 4; beat++) begin
      reset_between_operations();
      read_error_beat = beat;
      inject_read_error = 1;
      miss_before = miss_count;
      cpu_access(0, 32'h0001_8000 + beat*32, 0, 0, 2, actual, error);
      if (!error) begin
        $error("Read error beat %0d was not reported", beat);
        failures++;
      end
      inject_read_error = 0;
      expect_read(32'h0001_8000 + beat*32, memory[(32'h0001_8000 + beat*32) >> 2]);
      if (miss_count <= miss_before + 1) begin
        $error("Failed refill beat %0d installed a valid line", beat);
        failures++;
      end
    end
    read_error_beat = 2;
  endtask

  task automatic run_axi_writeback_error_matrix;
    logic [31:0] ignored;
    logic [31:0] line0;
    logic [31:0] line1;
    logic [31:0] line2;
    bit error;
    int stride;
    stride = CACHE_SETS * 32;

    reset_between_operations();
    line0 = 32'h0001_9000;
    line1 = line0 + stride;
    line2 = line0 + 2*stride;
    cpu_access(1, line0, 32'hbeef_9000, 4'hf, 2, ignored, error);
    expect_read(line1, memory[line1 >> 2]);
    inject_write_error = 1;
    cpu_access(0, line2, 0, 0, 2, ignored, error);
    if (!error) begin $error("Dirty eviction writeback error was not reported"); failures++; end
    inject_write_error = 0;
    expect_read(line0, 32'hbeef_9000);

    reset_between_operations();
    line0 = 32'h0001_a000;
    cpu_access(1, line0, 32'hbeef_a000, 4'hf, 2, ignored, error);
    inject_write_error = 1;
    @(negedge clk); maint_valid = 1; maint_cmd = 2'd0;
    do @(posedge clk); while (!maint_ready);
    @(negedge clk); maint_valid = 0;
    do @(posedge clk); while (!maint_done);
    if (!maint_error) begin $error("Maintenance writeback error was not reported"); failures++; end
    inject_write_error = 0;
    expect_read(line0, 32'hbeef_a000);
  endtask

  task automatic run_lru_adversarial_walk;
    logic [31:0] line0;
    logic [31:0] line1;
    logic [31:0] line2;
    int stride;
    stride = CACHE_SETS * 32;
    for (int set_idx = 0; set_idx < 8; set_idx++) begin
      reset_between_operations();
      line0 = 32'h0001_b000 + set_idx*32;
      line1 = line0 + stride;
      line2 = line0 + 2*stride;
      expect_read(line0, memory[line0 >> 2]);
      expect_read(line1, memory[line1 >> 2]);
      expect_read((set_idx[0]) ? line0 : line1, memory[((set_idx[0]) ? line0 : line1) >> 2]);
      expect_read(line2, memory[line2 >> 2]);
    end
  endtask

  task automatic run_invalid_way_preference_matrix;
    logic [31:0] line0;
    logic [31:0] line1;
    int stride;
    int set_points [0:2];
    int evict_before;
    if (CACHE_WAYS < 2) return;
    stride = CACHE_SETS * 32;
    set_points[0] = 0;
    set_points[1] = CACHE_SETS / 2;
    set_points[2] = CACHE_SETS - 1;
    for (int idx = 0; idx < 3; idx++) begin
      reset_between_operations();
      line0 = 32'h0001_c000 + set_points[idx]*32;
      line1 = line0 + stride;
      evict_before = eviction_count;
      expect_read(line0, memory[line0 >> 2]);
      expect_read(line1, memory[line1 >> 2]);
      if (eviction_count != evict_before) begin
        $error("Invalid-way preference failed for set %0d", set_points[idx]);
        failures++;
      end
    end
  endtask

  task automatic run_maintenance_dirty_error_boundary;
    logic [31:0] ignored;
    logic [31:0] addr;
    int set_points [0:2];
    bit error;
    set_points[0] = 0;
    set_points[1] = CACHE_SETS / 2;
    set_points[2] = CACHE_SETS - 1;
    for (int command = 0; command < 3; command += 2) begin
      for (int idx = 0; idx < 3; idx++) begin
        reset_between_operations();
        addr = 32'h0001_d000 + set_points[idx]*32;
        cpu_access(1, addr, 32'had00_0000 ^ 32'(command) ^ 32'(idx), 4'hf, 2,
                   ignored, error);
        inject_write_error = 1;
        @(negedge clk); maint_valid = 1; maint_cmd = command[1:0];
        do @(posedge clk); while (!maint_ready);
        @(negedge clk); maint_valid = 0;
        do @(posedge clk); while (!maint_done);
        if (!maint_error) begin
          $error("Dirty boundary maintenance command %0d set %0d missed error", command,
                 set_points[idx]);
          failures++;
        end
        inject_write_error = 0;
        expect_read(addr, 32'had00_0000 ^ 32'(command) ^ 32'(idx));
      end
    end
  endtask

  task automatic run_maintenance_backpressure_boundary;
    logic [31:0] ignored;
    logic [31:0] addrs [0:2];
    logic [31:0] vals [0:2];
    int set_points [0:2];
    bit error;
    set_points[0] = 0;
    set_points[1] = CACHE_SETS / 2;
    set_points[2] = CACHE_SETS - 1;
    for (int command = 0; command < 3; command++) begin
      reset_between_operations();
      for (int idx = 0; idx < 3; idx++) begin
        addrs[idx] = 32'h0001_e000 + set_points[idx]*32;
        vals[idx] = 32'hbc00_0000 ^ 32'(command) ^ 32'(idx);
        cpu_access(1, addrs[idx], vals[idx], 4'hf, 2, ignored, error);
      end
      aw_stall_budget = 2;
      w_stall_budget = 2;
      b_delay_cfg = 2;
      issue_maintenance(command[1:0]);
      b_delay_cfg = 0;
      if (command == 0 || command == 2) begin
        for (int idx = 0; idx < 3; idx++) begin
          if (memory[addrs[idx] >> 2] !== vals[idx]) begin
            $error("Maintenance backpressure command %0d did not flush set %0d", command,
                   set_points[idx]);
            failures++;
          end
        end
      end
    end
  endtask

  function automatic int cached_way(input logic [31:0] addr);
    int set_idx;
    logic [31:0] expected_tag;
    set_idx = (addr >> 5) & (CACHE_SETS - 1);
    expected_tag = addr >> (5 + $clog2(CACHE_SETS));
    cached_way = -1;
    for (int way = 0; way < CACHE_WAYS; way++) begin
      if (dut.valid_bits[way][set_idx] && 32'(dut.tags[way][set_idx]) == expected_tag)
        cached_way = way;
    end
  endfunction

  task automatic inject_data_fault(
    input logic [31:0] addr,
    input int word,
    input int bit_a,
    input int bit_b
  );
    int way;
    int set_idx;
    way = cached_way(addr);
    set_idx = (addr >> 5) & (CACHE_SETS - 1);
    if (way < 0) begin
      $error("SECDED injection address is not cached: %08x", addr);
      failures++;
    end else begin
      dut.data_mem[way][set_idx][word][bit_a] = ~dut.data_mem[way][set_idx][word][bit_a];
      if (bit_b >= 0)
        dut.data_mem[way][set_idx][word][bit_b] = ~dut.data_mem[way][set_idx][word][bit_b];
    end
  endtask

  task automatic inject_ecc_fault(input logic [31:0] addr, input int word, input int bit_idx);
    int way;
    int set_idx;
    way = cached_way(addr);
    set_idx = (addr >> 5) & (CACHE_SETS - 1);
    if (way < 0) begin
      $error("SECDED ECC injection address is not cached: %08x", addr);
      failures++;
    end else begin
      dut.ecc_mem[way][set_idx][word][bit_idx] = ~dut.ecc_mem[way][set_idx][word][bit_idx];
    end
  endtask

  task automatic run_secded_ras_matrix;
    logic [31:0] ignored;
    logic [31:0] actual;
    logic [31:0] addr0;
    logic [31:0] addr1;
    logic [31:0] addr2;
    logic [31:0] expected;
    bit error;
    int stride;
    int corrected_before;
    int uncorrectable_before;
    int scrub_before;
    int aw_before;
    int ar_before;

    if (!CACHE_SECDED_ENABLE) begin
      $error("secded_ras_matrix requires CACHE_SECDED_ENABLE=1");
      failures++;
      return;
    end
    stride = CACHE_SETS * 32;
    addr0 = 32'h0000_4000;
    addr1 = addr0 + stride;
    addr2 = addr0 + 2*stride;

    expected = memory[addr0 >> 2];
    expect_read(addr0, expected);
    corrected_before = ecc_corrected_count;
    scrub_before = ecc_scrub_count;
    inject_data_fault(addr0, 0, 5, -1);
    expect_read(addr0, expected);
    @(posedge clk);
    if (ecc_corrected_count <= corrected_before || ecc_scrub_count <= scrub_before) begin
      $error("Single data-bit SECDED fault was not corrected and scrubbed");
      failures++;
    end
    $display("RAS_COVER|point=single_data_corrected_clean|status=COVERED");

    corrected_before = ecc_corrected_count;
    inject_ecc_fault(addr0, 0, 0);
    expect_read(addr0, expected);
    @(posedge clk);
    if (ecc_corrected_count <= corrected_before) begin
      $error("Single ECC-bit fault was not corrected");
      failures++;
    end
    $display("RAS_COVER|point=single_ecc_corrected|status=COVERED");

    uncorrectable_before = ecc_uncorrectable_count;
    inject_data_fault(addr0, 0, 1, 7);
    cpu_access(0, addr0, 0, 0, 2, actual, error);
    @(posedge clk);
    if (!error || ecc_uncorrectable_count <= uncorrectable_before) begin
      $error("Double-bit clean-line fault was not contained");
      failures++;
    end
    $display("RAS_COVER|point=double_data_detected_clean|status=COVERED");

    reset_between_operations();
    cpu_access(1, addr0, 32'hcafe_600d, 4'hf, 2, ignored, error);
    expect_read(addr1, memory[addr1 >> 2]);
    inject_data_fault(addr0, 0, 9, -1);
    expect_read(addr2, memory[addr2 >> 2]);
    if (memory[addr0 >> 2] !== 32'hcafe_600d) begin
      $error("Corrected dirty victim was not written back with repaired data");
      failures++;
    end
    $display("RAS_COVER|point=single_data_corrected_dirty_writeback|status=COVERED");

    reset_between_operations();
    cpu_access(1, addr0, 32'hdead_700d, 4'hf, 2, ignored, error);
    expect_read(addr1, memory[addr1 >> 2]);
    inject_data_fault(addr0, 0, 2, 3);
    aw_before = axi_aw_handshakes;
    ar_before = axi_ar_handshakes;
    cpu_access(0, addr2, 0, 0, 2, actual, error);
    if (!error || axi_aw_handshakes != aw_before || axi_ar_handshakes != ar_before) begin
      $error("Uncorrectable dirty victim escaped containment");
      failures++;
    end
    $display("RAS_COVER|point=double_data_blocks_dirty_eviction|status=COVERED");

    reset_between_operations();
    cpu_access(1, addr0, 32'h1234_abcd, 4'hf, 2, ignored, error);
    inject_data_fault(addr0, 0, 11, -1);
    issue_maintenance(2'd0);
    if (memory[addr0 >> 2] !== 32'h1234_abcd) begin
      $error("Maintenance did not write corrected dirty data");
      failures++;
    end
    $display("RAS_COVER|point=single_data_corrected_maintenance|status=COVERED");

    reset_between_operations();
    cpu_access(1, addr0, 32'h7654_3210, 4'hf, 2, ignored, error);
    inject_data_fault(addr0, 0, 12, 13);
    @(negedge clk); maint_valid = 1; maint_cmd = 2'd0;
    do @(posedge clk); while (!maint_ready);
    @(negedge clk); maint_valid = 0;
    do @(posedge clk); while (!maint_done);
    if (!maint_error || memory[addr0 >> 2] === 32'h7654_3210) begin
      $error("Maintenance did not preserve an uncorrectable dirty line");
      failures++;
    end
    $display("RAS_COVER|point=double_data_detected_maintenance|status=COVERED");
    $display("RAS_RESULT|corrected=%0d|uncorrectable=%0d|scrubs=%0d|status=%s",
             ecc_corrected_count, ecc_uncorrectable_count, ecc_scrub_count,
             failures == 0 ? "PASS" : "FAIL");
  endtask

  task automatic reset_between_operations;
    @(negedge clk); rst_n = 0;
    repeat (3) @(posedge clk);
    @(negedge clk); rst_n = 1;
    repeat (3) @(posedge clk);
  endtask

  task automatic reset_during_writeback;
    logic [31:0] ignored;
    bit error;
    cpu_access(1, 32'h0000_5000, 32'h1111_0001, 4'hf, 2, ignored, error);
    expect_read(32'h0000_5800, memory[32'h5800 >> 2]);
    @(negedge clk);
    cpu_req_valid = 1;
    cpu_req_addr = 32'h0000_6000;
    cpu_req_write = 0;
    cpu_req_wdata = 0;
    cpu_req_wstrb = 0;
    cpu_req_size = 2;
    cpu_req_id = next_id[7:0];
    next_id++;
    do @(posedge clk); while (!cpu_req_ready);
    @(negedge clk); cpu_req_valid = 0;
    do @(posedge clk); while (mon_state != 5'd3);
    reset_between_operations();
  endtask

  task automatic run_random;
    logic [31:0] model [int unsigned];
    logic [31:0] actual, data;
    logic [31:0] addr;
    logic [3:0] strobes;
    bit error;
    int writes = 0;
    int reads = 0;
    int conflicts = 0;
    int injected = 0;
    int resets = 0;
    int observed_errors = 0;
    int full_strobes = 0;
    int single_strobes = 0;
    int partial_strobes = 0;
    int span_words = random_addr_span / 4;
    void'($urandom(random_seed_cfg));
    for (int n = 0; n < random_operations; n++) begin
      int index;
      bit force_conflict = $urandom_range(0, 99) < random_conflict_percent;
      if (random_addr_profile == "sequential")
        index = n % span_words;
      else if (random_addr_profile == "hot-set")
        index = (($urandom_range(0, 7) * 64) + $urandom_range(0, 3) * 8 +
                 $urandom_range(0, 7)) % span_words;
      else if (random_addr_profile == "two-line-conflict") begin
        index = (((n % 2) * 128 * 8) + ((n / 2) % 8)) % span_words;
        conflicts++;
      end
      else if (random_addr_profile == "same-set" || force_conflict) begin
        // A 4 KiB stride maps to the same set in both equal-capacity geometries.
        index = (($urandom_range(0, 15) * 128 * 8) + $urandom_range(0, 7)) % span_words;
        conflicts++;
      end else
        index = $urandom_range(0, span_words - 1);
      addr = random_addr_base + index*4;
      if (n == random_reset_operation) begin
        if (random_reset_phase == "refill") run_reset_mid_refill();
        else if (random_reset_phase == "writeback") reset_during_writeback();
        else reset_between_operations();
        model.delete();
        resets++;
      end
      if (model.exists(addr >> 2) == 0) model[addr >> 2] = memory[addr >> 2];

      if (random_strobe_profile == "single-byte")
        strobes = 4'b0001 << $urandom_range(0, 3);
      else if (random_strobe_profile == "mixed") begin
        strobes = 4'($urandom_range(1, 15));
        if (strobes == 4'hf) strobes = 4'b0110;
      end else
        strobes = 4'hf;

      inject_read_error = 0;
      inject_write_error = 0;
      if ($urandom_range(0, 99) < random_error_percent) begin
        inject_read_error = 1;
        inject_write_error = 1;
        injected++;
      end

      if ($urandom_range(0, 99) >= random_read_percent) begin
        data = $urandom;
        if (strobes == 4'hf) full_strobes++;
        else if (strobes == 4'b0001 || strobes == 4'b0010 ||
                 strobes == 4'b0100 || strobes == 4'b1000) single_strobes++;
        else partial_strobes++;
        cpu_access(1, addr, data, strobes, 2, actual, error);
        writes++;
        if (!error) begin
          for (int byte_idx = 0; byte_idx < 4; byte_idx++)
            if (strobes[byte_idx])
              model[addr >> 2][byte_idx*8 +: 8] = data[byte_idx*8 +: 8];
        end
      end else begin
        cpu_access(0, addr, 0, 0, 2, actual, error);
        reads++;
        if (!error && actual !== model[addr >> 2]) begin
          $error("Random mismatch addr=%08x expected=%08x actual=%08x",
                 addr, model[addr >> 2], actual);
          failures++;
        end
      end
      if (error) observed_errors++;
      inject_read_error = 0;
      inject_write_error = 0;
    end
    $display("RANDOM_RESULT|requested_ops=%0d|reads=%0d|writes=%0d|conflicts=%0d|injections=%0d|error_responses=%0d|resets=%0d|full_strobes=%0d|single_strobes=%0d|partial_strobes=%0d|bp_pct=%0d|axi_stalls=%0d|axi_valid=%0d|addr_profile=%s|strobe_profile=%s",
             random_operations, reads, writes, conflicts, injected, observed_errors,
             resets, full_strobes, single_strobes, partial_strobes, bp_percent,
             axi_stall_cycles, axi_valid_cycles, random_addr_profile, random_strobe_profile);
  endtask

  task automatic run_cross_matrix;
    logic [31:0] ignored;
    bit error;
    // Read/write hit/miss, offset, and strobe combinations.
    for (int word = 0; word < 8; word++) begin
      expect_read(32'h0000_a000 + word*4, memory[(32'h0000_a000 >> 2) + word]);
      cpu_access(1, 32'h0000_a000 + word*4, 32'hf0e1_d2c3 ^ word,
                 4'hf, 2, ignored, error);
      cpu_access(1, 32'h0000_a000 + word*4, 32'h0102_0304 ^ word,
                 4'b0001 << (word % 4), 2, ignored, error);
      cpu_access(1, 32'h0000_a000 + word*4, 32'h89ab_cdef ^ word,
                 word[0] ? 4'b0110 : 4'b1001, 2, ignored, error);
    end

    // Clean way-0 victim.
    reset_between_operations();
    expect_read(32'h0000_7000, memory[32'h7000 >> 2]);
    expect_read(32'h0000_7800, memory[32'h7800 >> 2]);
    expect_read(32'h0000_7800, memory[32'h7800 >> 2]);
    expect_read(32'h0000_8000, memory[32'h8000 >> 2]);

    // Clean way-1 victim.
    reset_between_operations();
    expect_read(32'h0000_7000, memory[32'h7000 >> 2]);
    expect_read(32'h0000_7800, memory[32'h7800 >> 2]);
    expect_read(32'h0000_7000, memory[32'h7000 >> 2]);
    expect_read(32'h0000_8000, memory[32'h8000 >> 2]);

    // Dirty way-0 victim.
    reset_between_operations();
    cpu_access(1, 32'h0000_7000, 32'hd100_0000, 4'hf, 2, ignored, error);
    expect_read(32'h0000_7800, memory[32'h7800 >> 2]);
    expect_read(32'h0000_7800, memory[32'h7800 >> 2]);
    expect_read(32'h0000_8000, memory[32'h8000 >> 2]);

    // Dirty way-1 victim.
    reset_between_operations();
    expect_read(32'h0000_7000, memory[32'h7000 >> 2]);
    cpu_access(1, 32'h0000_7800, 32'hd100_0001, 4'hf, 2, ignored, error);
    expect_read(32'h0000_7000, memory[32'h7000 >> 2]);
    expect_read(32'h0000_8000, memory[32'h8000 >> 2]);

    // Every maintenance command scans invalid, clean, and dirty lines.
    for (int command = 0; command < 3; command++) begin
      reset_between_operations();
      expect_read(32'h0000_b000 + command*32, memory[(32'hb000 + command*32) >> 2]);
      cpu_access(1, 32'h0000_b800 + command*32, 32'hcafe_1000 + command,
                 4'hf, 2, ignored, error);
      issue_maintenance(command[1:0]);
    end
  endtask

  task automatic run_performance_workload;
    logic [31:0] ignored;
    bit error;
    run_random();
    cpu_access(1, 32'h0000_c000, 32'hface_0001, 4'hf, 2, ignored, error);
    issue_maintenance(2'd0);
    expect_read(32'h0000_c800, memory[32'hc800 >> 2]);
    issue_maintenance(2'd1);
    cpu_access(1, 32'h0000_d000, 32'hface_0002, 4'hf, 2, ignored, error);
    issue_maintenance(2'd2);
  endtask

  initial begin
    if (!$value$plusargs("TEST=%s", test_name)) test_name = "smoke";
    void'($value$plusargs("STALL_MOD=%d", stall_mod));
    void'($value$plusargs("BP_PCT=%d", bp_percent));
    void'($value$plusargs("OPS=%d", random_operations));
    void'($value$plusargs("READ_PCT=%d", random_read_percent));
    void'($value$plusargs("CONFLICT_PCT=%d", random_conflict_percent));
    void'($value$plusargs("ERROR_PCT=%d", random_error_percent));
    void'($value$plusargs("RESET_OP=%d", random_reset_operation));
    void'($value$plusargs("SEED=%d", random_seed_cfg));
    void'($value$plusargs("ADDR_BASE=%h", random_addr_base));
    void'($value$plusargs("ADDR_SPAN=%h", random_addr_span));
    void'($value$plusargs("RESET_PHASE=%s", random_reset_phase));
    void'($value$plusargs("STROBE_PROFILE=%s", random_strobe_profile));
    void'($value$plusargs("ADDR_PROFILE=%s", random_addr_profile));
    model_final_flush = $test$plusargs("MODEL_FINAL_FLUSH");
    for (int i = 0; i < 65536; i++) begin
      memory[i] = 32'h1000_0000 ^ i;
      memory_touched[i] = 0;
    end
    reset_dut();
    case (test_name)
      "smoke": run_smoke();
      "read_miss": run_read_miss();
      "read_hit": run_read_hit();
      "write_miss": run_write_miss();
      "write_hit": run_write_hit();
      "clean_evict": run_clean_evict();
      "dirty_evict": run_dirty_evict();
      "backpressure": run_backpressure();
      "read_error": run_read_error();
      "byte_strobes": run_byte_strobes();
      "byte_strobe_lane_matrix": run_byte_strobe_lane_matrix();
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
      "set_way_sweep_toggle": run_set_way_sweep_toggle();
      "maintenance_boundary_sets": run_maintenance_boundary_sets();
      "reset_refill_beat_matrix": run_reset_refill_beat_matrix();
      "reset_writeback_beat_matrix": run_reset_writeback_beat_matrix();
      "reset_maintenance_scan_matrix": run_reset_maintenance_scan_matrix();
      "axi_read_error_beat_matrix": run_axi_read_error_beat_matrix();
      "axi_writeback_error_matrix": run_axi_writeback_error_matrix();
      "lru_adversarial_walk": run_lru_adversarial_walk();
      "invalid_way_preference_matrix": run_invalid_way_preference_matrix();
      "maintenance_dirty_error_boundary": run_maintenance_dirty_error_boundary();
      "maintenance_backpressure_boundary": run_maintenance_backpressure_boundary();
      "secded_ras_matrix": run_secded_ras_matrix();
      "cross_matrix": run_cross_matrix();
      "performance_workload": run_performance_workload();
      "random": run_random();
      default: begin $error("Unknown TEST=%s", test_name); failures++; end
    endcase
    if (model_final_flush) issue_maintenance(2'd0);
    repeat (5) @(posedge clk);
    if (request_count != response_count) begin
      $error("Request/response count mismatch %0d/%0d", request_count, response_count);
      failures++;
    end
    for (int i = 0; i < 65536; i++) begin
      if (memory_touched[i])
        dut.u_trace_observer.emit_final_memory(i << 2, memory[i]);
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
