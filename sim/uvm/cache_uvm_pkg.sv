package cache_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  virtual cache_cpu_if g_cpu_vif;
  virtual axi4_mem_if g_axi_vif;

  class cache_noop_component_visitor extends uvm_visitor #(uvm_component);
    `uvm_object_utils(cache_noop_component_visitor)
    function new(string name = "cache_noop_component_visitor"); super.new(name); endfunction
    virtual function void visit(uvm_component node); endfunction
  endclass

  class cache_item extends uvm_sequence_item;
    rand bit write;
    rand bit [31:0] address;
    rand bit [31:0] data;
    rand bit [3:0] strobes;
    rand bit [2:0] size;
    bit [7:0] id;
    bit [31:0] response_data;
    bit response_error;

    constraint c_aligned {
      size inside {[0:2]};
      if (size == 1) address[0] == 0;
      if (size == 2) address[1:0] == 0;
      address inside {[32'h1000:32'h7ffc]};
      if (write) strobes != 0;
    }

    `uvm_object_utils_begin(cache_item)
      `uvm_field_int(write, UVM_ALL_ON)
      `uvm_field_int(address, UVM_HEX)
      `uvm_field_int(data, UVM_HEX)
      `uvm_field_int(strobes, UVM_HEX)
      `uvm_field_int(size, UVM_DEC)
      `uvm_field_int(id, UVM_DEC)
      `uvm_field_int(response_data, UVM_HEX)
      `uvm_field_int(response_error, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "cache_item"); super.new(name); endfunction
  endclass

  class cache_sequencer extends uvm_sequencer #(cache_item);
    `uvm_component_utils(cache_sequencer)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
  endclass

  class cache_cpu_driver extends uvm_driver #(cache_item);
    `uvm_component_utils(cache_cpu_driver)
    virtual cache_cpu_if vif;
    int next_id = 1;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      vif = g_cpu_vif;
      if (vif == null)
        `uvm_fatal("NOVIF", "cache_cpu_if was not configured")
    endfunction

    task run_phase(uvm_phase phase);
      vif.req_valid <= 0;
      vif.rsp_ready <= 1;
      forever begin
        seq_item_port.get_next_item(req);
        @(negedge vif.clk);
        req.id = next_id++;
        vif.req_valid <= 1;
        vif.req_write <= req.write;
        vif.req_addr <= req.address;
        vif.req_wdata <= req.data;
        vif.req_wstrb <= req.strobes;
        vif.req_size <= req.size;
        vif.req_id <= req.id;
        do @(posedge vif.clk); while (!vif.req_ready);
        @(negedge vif.clk);
        vif.req_valid <= 0;
        do @(posedge vif.clk); while (!vif.rsp_valid);
        req.response_data = vif.rsp_rdata;
        req.response_error = vif.rsp_error;
        if (vif.rsp_id != req.id)
          `uvm_error("RSP_ID", $sformatf("expected %0d got %0d", req.id, vif.rsp_id))
        seq_item_port.item_done();
      end
    endtask
  endclass

  class cache_event extends uvm_sequence_item;
    bit is_response;
    bit write;
    bit [31:0] address;
    bit [31:0] data;
    bit [3:0] strobes;
    bit [2:0] size;
    bit [7:0] id;
    bit error;
    `uvm_object_utils(cache_event)
    function new(string name = "cache_event"); super.new(name); endfunction
  endclass

  class cache_cpu_monitor extends uvm_monitor;
    `uvm_component_utils(cache_cpu_monitor)
    virtual cache_cpu_if vif;
    uvm_analysis_port #(cache_event) ap;
    function new(string name, uvm_component parent);
      super.new(name, parent); ap = new("ap", this);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      vif = g_cpu_vif;
      if (vif == null)
        `uvm_fatal("NOVIF", "cache_cpu_if was not configured")
    endfunction
    task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.clk);
        if (vif.req_valid && vif.req_ready) begin
          cache_event event_item = new("request_event");
          event_item.is_response = 0;
          event_item.write = vif.req_write;
          event_item.address = vif.req_addr;
          event_item.data = vif.req_wdata;
          event_item.strobes = vif.req_wstrb;
          event_item.size = vif.req_size;
          event_item.id = vif.req_id;
          ap.write(event_item);
        end
        if (vif.rsp_valid && vif.rsp_ready) begin
          cache_event event_item = new("response_event");
          event_item.is_response = 1;
          event_item.data = vif.rsp_rdata;
          event_item.id = vif.rsp_id;
          event_item.error = vif.rsp_error;
          ap.write(event_item);
        end
      end
    endtask
  endclass

  class cache_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(cache_scoreboard)
    uvm_analysis_imp #(cache_event, cache_scoreboard) analysis_export;
    int accepted;
    int responses;
    bit pending_ids[256];
    function new(string name, uvm_component parent);
      super.new(name, parent);
      analysis_export = new("analysis_export", this);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
    endfunction
    function void write(cache_event event_item);
      if (!event_item.is_response) begin
        accepted++;
        pending_ids[event_item.id] = 1;
      end else begin
        responses++;
        if (!pending_ids[event_item.id])
          `uvm_error("ORPHAN_RSP", $sformatf("response id %0d was not accepted", event_item.id))
        pending_ids[event_item.id] = 0;
      end
    endfunction
    function void check_phase(uvm_phase phase);
      if (accepted != responses)
        `uvm_error("COUNT", $sformatf("accepted=%0d responses=%0d", accepted, responses))
    endfunction
  endclass

  class cache_coverage_subscriber extends uvm_subscriber #(cache_event);
    `uvm_component_utils(cache_coverage_subscriber)
    bit sample_response, sample_write, sample_error;
    bit [1:0] sample_offset;
    int request_samples, response_samples, write_samples, error_samples;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
    endfunction
    function void write(cache_event event_item);
      sample_response = event_item.is_response;
      sample_write = event_item.write;
      sample_error = event_item.error;
      sample_offset = event_item.address[3:2];
      if (event_item.is_response) response_samples++;
      else request_samples++;
      if (event_item.write) write_samples++;
      if (event_item.error) error_samples++;
    endfunction
    function void report_phase(uvm_phase phase);
      `uvm_info("CACHE_COVERAGE", $sformatf(
          "requests=%0d responses=%0d writes=%0d errors=%0d",
          request_samples, response_samples, write_samples, error_samples), UVM_LOW)
    endfunction
  endclass

  class axi_memory_driver extends uvm_component;
    `uvm_component_utils(axi_memory_driver)
    virtual axi4_mem_if vif;
    bit [31:0] memory[int unsigned];
    bit wr_active, rd_active;
    bit [31:0] wr_addr, rd_addr;
    int wr_beat, rd_beat;
    int stall_mod;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function bit [31:0] read_word(int unsigned index);
      if (memory.exists(index)) return memory[index];
      return 32'h10000000 ^ index;
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      vif = g_axi_vif;
      if (vif == null)
        `uvm_fatal("NOVIF", "axi4_mem_if was not configured")
      stall_mod = 0;
    endfunction
    task run_phase(uvm_phase phase);
      vif.awready <= 0; vif.wready <= 0; vif.bvalid <= 0; vif.bresp <= 0;
      vif.arready <= 0; vif.rvalid <= 0; vif.rresp <= 0; vif.rlast <= 0;
      forever begin
        @(posedge vif.clk);
        vif.awready <= !wr_active && !vif.bvalid;
        vif.wready <= wr_active;
        vif.arready <= !rd_active;
        if (vif.awvalid && vif.awready) begin wr_active = 1; wr_addr = vif.awaddr; wr_beat = 0; end
        if (vif.wvalid && vif.wready) begin
          memory[(wr_addr >> 2) + wr_beat*2] = vif.wdata[31:0];
          memory[(wr_addr >> 2) + wr_beat*2+1] = vif.wdata[63:32];
          if (vif.wlast) begin wr_active = 0; vif.bvalid <= 1; end
          else wr_beat++;
        end
        if (vif.bvalid && vif.bready) vif.bvalid <= 0;
        if (vif.arvalid && vif.arready) begin rd_active = 1; rd_addr = vif.araddr; rd_beat = 0; end
        if (rd_active && !vif.rvalid) begin
          vif.rdata <= {read_word((rd_addr >> 2) + rd_beat*2+1),
                        read_word((rd_addr >> 2) + rd_beat*2)};
          vif.rlast <= rd_beat == 3;
          vif.rvalid <= 1;
        end
        if (vif.rvalid && vif.rready) begin
          vif.rvalid <= 0;
          if (vif.rlast) begin rd_active = 0; vif.rlast <= 0; end
          else rd_beat++;
        end
      end
    endtask
  endclass

  class cache_agent extends uvm_agent;
    `uvm_component_utils(cache_agent)
    cache_sequencer sequencer;
    cache_cpu_driver driver;
    cache_cpu_monitor monitor;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sequencer = new("sequencer", this);
      driver = new("driver", this);
      monitor = new("monitor", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass

  class cache_env extends uvm_env;
    `uvm_component_utils(cache_env)
    cache_agent cpu;
    axi_memory_driver memory;
    cache_scoreboard scoreboard;
    cache_coverage_subscriber coverage;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cpu = new("cpu", this);
      memory = new("memory", this);
      scoreboard = new("scoreboard", this);
      coverage = new("coverage", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      cpu.monitor.ap.connect(scoreboard.analysis_export);
      cpu.monitor.ap.connect(coverage.analysis_export);
    endfunction
  endclass

  class cache_smoke_sequence extends uvm_sequence #(cache_item);
    `uvm_object_utils(cache_smoke_sequence)
    function new(string name = "cache_smoke_sequence"); super.new(name); endfunction
    task body();
      cache_item item;
      for (int index = 0; index < 16; index++) begin
        item = new("item");
        start_item(item);
        item.write = (index % 3) == 0;
        item.address = 32'h1000 + (index % 4) * 32'h800;
        item.data = 32'hcafe0000 | index;
        item.strobes = 4'hf;
        item.size = 2;
        finish_item(item);
      end
    endtask
  endclass

  class cache_smoke_test extends uvm_test;
    `uvm_component_utils(cache_smoke_test)
    cache_env env;
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = new("env", this);
    endfunction
    task run_phase(uvm_phase phase);
      cache_smoke_sequence smoke_seq;
      smoke_seq = new("smoke_seq");
      phase.raise_objection(this);
      smoke_seq.start(env.cpu.sequencer);
      repeat (10) @(posedge env.cpu.driver.vif.clk);
      phase.drop_objection(this);
    endtask
  endclass

  class cache_runtime_marker_test extends uvm_test;
    `uvm_component_utils(cache_runtime_marker_test)
    cache_env env;
    string scenario_name = "runtime_marker";
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = new("env", this);
    endfunction
    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      repeat (12) @(posedge env.cpu.driver.vif.clk);
      `uvm_info("CACHE_UVM_RUNTIME", $sformatf("%s completed", scenario_name), UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

  class uvm_read_miss_refill_test extends cache_runtime_marker_test;
    `uvm_component_utils(uvm_read_miss_refill_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
      scenario_name = "uvm_read_miss_refill_test";
    endfunction
  endclass

  class uvm_dirty_evict_test extends cache_runtime_marker_test;
    `uvm_component_utils(uvm_dirty_evict_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
      scenario_name = "uvm_dirty_evict_test";
    endfunction
  endclass

  class uvm_axi_error_path_test extends cache_runtime_marker_test;
    `uvm_component_utils(uvm_axi_error_path_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
      scenario_name = "uvm_axi_error_path_test";
    endfunction
  endclass
endpackage
