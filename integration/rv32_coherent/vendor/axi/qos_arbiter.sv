`timescale 1ns/1ps
module qos_arbiter #(
    parameter int REQUESTERS = 4,
    parameter int AGE_W = 6,
    parameter int STARVE_LIMIT = 32
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [REQUESTERS-1:0] req,
    input  logic [REQUESTERS*4-1:0] qos_flat,
    input  logic accept,
    output logic grant_valid,
    output logic [$clog2(REQUESTERS)-1:0] grant_idx,
    output logic age_override
);
  localparam int IDX_W = $clog2(REQUESTERS);
  logic [IDX_W-1:0] rr_ptr;
  logic found;
  logic [3:0] best_qos;
  logic [REQUESTERS*AGE_W-1:0] age;
  logic hold_valid;
  logic [IDX_W-1:0] hold_idx;
  logic hold_age_override;
  integer idx;

  function automatic [3:0] qos_at(input integer request_index);
    qos_at = qos_flat[request_index*4 +: 4];
  endfunction

  function automatic [AGE_W-1:0] age_at(input integer request_index);
    age_at = age[request_index*AGE_W +: AGE_W];
  endfunction

  /* verilator lint_off UNUSEDSIGNAL */
  function automatic [IDX_W-1:0] idx_cast(input integer value);
    idx_cast = value[IDX_W-1:0];
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  /* verilator lint_off WIDTHEXPAND */
  always_comb begin
    grant_valid = 1'b0;
    grant_idx = '0;
    age_override = 1'b0;
    found = 1'b0;
    best_qos = '0;
    idx = 0;

    // Once presented to a backpressured target, a grant is held until handshake.
    if (hold_valid) begin
      grant_valid = 1'b1;
      grant_idx = hold_idx;
      age_override = hold_age_override;
      found = 1'b1;
    end

    // Aged requests are considered in rotating order so the override remains fair.
    for (int off = 0; off < REQUESTERS; off++) begin
      idx = (rr_ptr + off) % REQUESTERS;
`ifdef BUG_AGE_DISABLE
      if (1'b0) begin
`else
      if (!found && req[idx] && age_at(idx) >= STARVE_LIMIT-1) begin
`endif
        grant_valid = 1'b1;
        grant_idx = idx_cast(idx);
        age_override = 1'b1;
        found = 1'b1;
      end
    end

    if (!found) begin
      for (int i = 0; i < REQUESTERS; i++) begin
        if (req[i] && (!grant_valid || qos_at(i) > best_qos)) begin
          best_qos = qos_at(i);
          grant_valid = 1'b1;
        end
      end
      found = 1'b0;
      for (int off = 0; off < REQUESTERS; off++) begin
        idx = (rr_ptr + off) % REQUESTERS;
        if (!found && req[idx] && qos_at(idx) == best_qos) begin
          grant_idx = idx_cast(idx);
          found = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rr_ptr <= '0;
      age <= '0;
      hold_valid <= 1'b0;
      hold_idx <= '0;
      hold_age_override <= 1'b0;
    end else begin
      if (hold_valid && accept) begin
        hold_valid <= 1'b0;
      end else if (!hold_valid && grant_valid && !accept) begin
        hold_valid <= 1'b1;
        hold_idx <= grant_idx;
        hold_age_override <= age_override;
      end
      for (int i = 0; i < REQUESTERS; i++) begin
        if (!req[i] || (accept && grant_valid && grant_idx == idx_cast(i)))
          age[i*AGE_W +: AGE_W] <= '0;
        else if (accept && age_at(i) != {AGE_W{1'b1}})
          age[i*AGE_W +: AGE_W] <= age_at(i) + 1'b1;
      end
      if (accept && grant_valid)
        rr_ptr <= grant_idx == REQUESTERS-1 ? '0 : grant_idx + 1'b1;
    end
  end
  /* verilator lint_on WIDTHEXPAND */
endmodule
