# Implemented Bug Diary

Only compile-time mutations present in RTL are listed.

## Dirty Update Skipped

- **Mutation:** `CACHE_BUG_DIRTY_SKIP`
- **Failure:** a modified line is treated as clean and discarded during replacement.
- **Detection:** `dirty_evict` observes stale backing memory.
- **Engineering relevance:** validates that the scoreboard checks externally visible writeback state, not only CPU responses.

## LRU Direction Inverted

- **Mutation:** `CACHE_BUG_LRU_INVERT`
- **Failure:** the most recently used way can be selected instead of the intended victim.
- **Detection:** the conflict sequence observes the wrong dirty-line writeback behavior.
- **Engineering relevance:** exercises replacement-policy checking with controlled same-set addresses.

## Refill Error Ignored

- **Mutation:** `CACHE_BUG_REFILL_ERROR_IGNORE`
- **Failure:** a line containing an AXI error is installed and returned as valid data.
- **Detection:** `read_error` expects a CPU-visible error and fails on silent success.
- **Engineering relevance:** demonstrates fault containment across AXI and cache state.

## Early WLAST

- **Mutation:** `CACHE_BUG_WLAST_EARLY`
- **Failure:** writeback terminates before all four cache-line beats are transferred.
- **Detection:** the AXI memory checker flags the wrong final-beat position and dirty data is incomplete.
- **Engineering relevance:** demonstrates burst-protocol and end-to-end memory checking.
- **Debug evidence:** [waveform-driven case study](hiring_manager_case_study.md).
