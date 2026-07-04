# Cache Architecture and Protocol

## Address Decomposition

For a 32-byte line and 64 sets:

- `address[4:0]`: byte offset within a line
- `address[10:5]`: set index
- `address[31:11]`: tag

Each line stores eight 32-bit words. Two words are transferred on every 64-bit AXI beat.

## Request Behavior

The CPU request is accepted only in `IDLE`. The controller latches address, operation, data, strobes, size, and transaction ID. Aligned 8-, 16-, and 32-bit requests are supported; a misaligned request returns an error without changing cache state.

A hit completes from the selected way. Stores merge bytes according to `wstrb`, regenerate parity, and mark the line dirty. A miss chooses an invalid way before consulting the per-set LRU bit.

## Miss Flow

1. Select victim.
2. If valid and dirty, issue a four-beat AXI writeback and wait for `B`.
3. Issue a four-beat AXI refill.
4. Buffer the complete line so a failed refill cannot partially install data.
5. Install tag, data, parity, valid, and clean state after a successful final beat.
6. Replay the original CPU request.

AXI read or write errors become CPU-visible errors. A failed refill does not install the new line. A failed writeback leaves the victim dirty.

## Maintenance

The maintenance sequencer scans every set and way. It supports flush, invalidate, and flush-then-invalidate. New CPU requests are blocked while maintenance is active. Dirty flushes use the same AXI writeback path as replacement.

