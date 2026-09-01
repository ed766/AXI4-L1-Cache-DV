module coherent_leaf_properties;
  (* gclk *) logic clk;
  logic reset_q = 1'b1;
  always_ff @(posedge clk) reset_q <= 1'b0;
  wire rst_n = !reset_q;

  (* anyseq *) logic grant_m0, grant_m1, grant_s0, grant_s1;
  (* anyseq *) logic enqueue, dequeue, fence_request;
  (* anyseq *) logic [1:0] enqueue_address, load_address;
  (* anyseq *) logic [7:0] enqueue_data;
  (* anyseq *) logic request_accept, response_accept, request_owner;
  (* anyseq *) logic publication_read;

  logic modified0, modified1, shared0, shared1;
  logic [1:0] fifo_count;
  logic [1:0] fifo_addr0, fifo_addr1;
  logic [7:0] fifo_data0, fifo_data1, last_dequeue_data;
  logic outstanding, recorded_owner;
  logic [7:0] memory_data;
  logic publication_complete;

  wire forward_tail = fifo_count == 2 && fifo_addr1 == load_address;
  wire forward_head = fifo_count != 0 && fifo_addr0 == load_address;
  wire forward_valid = forward_tail || forward_head;
  wire [7:0] forward_data = forward_tail ? fifo_data1 : fifo_data0;
  wire fence_done = fifo_count == 0;
  wire response_owner = recorded_owner;
  wire [7:0] publication_read_data = memory_data;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      modified0 <= 1'b0; modified1 <= 1'b0;
      shared0 <= 1'b0; shared1 <= 1'b0;
      fifo_count <= '0;
      fifo_addr0 <= '0; fifo_addr1 <= '0;
      fifo_data0 <= '0; fifo_data1 <= '0; last_dequeue_data <= '0;
      outstanding <= 1'b0; recorded_owner <= 1'b0;
      memory_data <= '0; publication_complete <= 1'b0;
    end else begin
      assume (!(grant_m0 && grant_m1));
      assume (!(grant_s0 && grant_s1));
      assume (!(enqueue && fifo_count == 2 && !dequeue));
      assume (!(dequeue && fifo_count == 0));
      assume (!(request_accept && outstanding && !response_accept));
      assume (!response_accept || outstanding);

      if (grant_m0) begin
        modified0 <= 1'b1; modified1 <= 1'b0;
        shared0 <= 1'b0; shared1 <= 1'b0;
      end else if (grant_m1) begin
        modified0 <= 1'b0; modified1 <= 1'b1;
        shared0 <= 1'b0; shared1 <= 1'b0;
      end else if (grant_s0) begin
        modified0 <= 1'b0;
        if (modified1) modified1 <= 1'b0;
        shared0 <= 1'b1; shared1 <= shared1 || modified1;
      end else if (grant_s1) begin
        modified1 <= 1'b0;
        if (modified0) modified0 <= 1'b0;
        shared1 <= 1'b1; shared0 <= shared0 || modified0;
      end

      case ({enqueue, dequeue})
        2'b10: begin
          if (fifo_count == 0) begin fifo_addr0 <= enqueue_address; fifo_data0 <= enqueue_data; end
          else begin fifo_addr1 <= enqueue_address; fifo_data1 <= enqueue_data; end
          fifo_count <= fifo_count + 1'b1;
        end
        2'b01: begin
          last_dequeue_data <= fifo_data0;
          fifo_addr0 <= fifo_addr1; fifo_data0 <= fifo_data1;
          fifo_count <= fifo_count - 1'b1;
          memory_data <= fifo_data0;
        end
        2'b11: begin
          last_dequeue_data <= fifo_data0;
          memory_data <= fifo_data0;
          if (fifo_count == 1) begin fifo_addr0 <= enqueue_address; fifo_data0 <= enqueue_data; end
          else begin
            fifo_addr0 <= fifo_addr1; fifo_data0 <= fifo_data1;
            fifo_addr1 <= enqueue_address; fifo_data1 <= enqueue_data;
          end
        end
        default: ;
      endcase

      if (fence_request && fence_done) publication_complete <= 1'b1;
      if (request_accept) begin outstanding <= 1'b1; recorded_owner <= request_owner; end
      if (response_accept) outstanding <= 1'b0;
    end
  end

`ifdef PROP_NO_DUAL_MODIFIED
  always_ff @(posedge clk) if (rst_n) begin
    assert (!(modified0 && modified1));
    cover (modified1 && $past(modified0));
  end
`endif
`ifdef PROP_NO_SHARED_MODIFIED
  always_ff @(posedge clk) if (rst_n) begin
    assert (!((modified0 && shared1) || (modified1 && shared0)));
    cover (shared0 && shared1 && $past(modified0 || modified1));
  end
`endif
`ifdef PROP_FIFO_ORDER
  always_ff @(posedge clk) if (rst_n && $past(rst_n)) begin
    if ($past(dequeue && fifo_count != 0)) assert (last_dequeue_data == $past(fifo_data0));
    cover (fifo_count == 2 && $past(fifo_count) == 1);
  end
`endif
`ifdef PROP_FORWARDING
  always_ff @(posedge clk) if (rst_n) begin
    if (forward_tail) assert (forward_valid && forward_data == fifo_data1);
    cover (forward_tail);
  end
`endif
`ifdef PROP_FENCE
  always_ff @(posedge clk) if (rst_n) begin
    if (fence_done) assert (fifo_count == 0);
    cover (fence_request && fence_done && $past(fifo_count) != 0);
  end
`endif
`ifdef PROP_PUBLICATION
  always_ff @(posedge clk) if (rst_n) begin
    if (publication_complete && publication_read) assert (publication_read_data == memory_data);
    cover (publication_complete && publication_read);
  end
`endif
`ifdef PROP_RESPONSE_ROUTE
  always_ff @(posedge clk) if (rst_n) begin
    if (response_accept) assert (response_owner == recorded_owner);
    cover (response_accept && outstanding);
  end
`endif
`ifdef PROP_RESET_EPOCH
  always_ff @(posedge clk) if (rst_n) begin
    if (response_accept) assert (outstanding);
    cover (response_accept && outstanding && $past(request_accept));
  end
`endif
endmodule
