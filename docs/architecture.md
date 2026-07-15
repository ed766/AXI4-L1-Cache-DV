# Cache Architecture and Protocol

## Address Decomposition

For the baseline 32-byte line and 64-set, 2-way geometry:

- `address[4:0]`: byte offset within a line
- `address[10:5]`: set index
- `address[31:11]`: tag

The equal-capacity direct-mapped variant uses 128 sets, so `address[11:5]` is the index and `address[31:12]` is the tag. Both geometries contain 128 total lines and therefore remain 4 KiB.

Each line stores eight 32-bit words. Two words are transferred on every 64-bit AXI beat. The baseline stores one parity bit per word. The optional SECDED variant stores a seven-bit code per word; parity and SECDED are mutually exclusive elaboration-time configurations.

## Request Behavior

The CPU request is accepted only in `IDLE`. The controller latches address, operation, data, strobes, size, and transaction ID. Aligned 8-, 16-, and 32-bit requests are supported; a misaligned request returns an error without changing cache state.

A hit completes from the selected way. Stores merge bytes according to `wstrb`, regenerate integrity metadata, and mark the line dirty. In SECDED mode, a single-bit data or code fault is corrected and a read scrubs the repaired word; a double-bit fault returns `cpu_rsp_error` without modifying the line. A 2-way miss chooses an invalid way before consulting the per-set LRU bit; direct-mapped mode always selects way zero and contains no active replacement policy.

## Miss Flow

1. Select victim.
2. If valid and dirty, issue a four-beat AXI writeback and wait for `B`.
3. Issue a four-beat AXI refill.
4. Buffer the complete line so a failed refill cannot partially install data.
5. Install tag, data, parity, valid, and clean state after a successful final beat.
6. Replay the original CPU request.

AXI read or write errors become CPU-visible errors. A failed refill does not install the new line. A failed writeback leaves the victim dirty.

In SECDED mode, writeback data passes through the decoder so a dirty line with a correctable fault reaches memory with repaired data. An uncorrectable dirty victim is contained before AXI writeback or refill begins.

## Maintenance

The maintenance sequencer scans every set and way. It supports flush, invalidate, and flush-then-invalidate. New CPU requests are blocked while maintenance is active. Dirty flushes use the same AXI writeback path as replacement.
