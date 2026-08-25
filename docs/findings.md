# Findings

## What worked

- The fixed dataset is compact enough for manual verification.
- Status filtering, deterministic sorting, date eligibility, partial allocation, and conservation invariants are explicit.
- The native PostgreSQL implementation tracks each confirmed PO lot independently, so supply is never reused and late supply is not applied retroactively.
- The verification harness compares expected, native, and real SQLazy-compiler results and runs the three requested edge cases.
- On 2026-08-25 the fixed dataset ran successfully in the official SQLazy web app and returned the expected three rows.
- The captured SQLazy `POSTGRES` output, base verification, and all three edge cases passed in a fresh PostgreSQL 14.18 (Homebrew) database and again in the Dockerized PostgreSQL 16 target.

## Where the abstraction leaked

- Progressive allocation needs state carried from one demand row to the next.
- A direct previous-row balance formulation ran in SQLazy but could not be compiled because the compiler rejected a current-alias reference. Recasting the logic as cumulative demand plus a running-min regulator made both runtime and compilation succeed.
- Numeric `nvl` generated PostgreSQL that compared numbers with empty strings. Replacing it with `isnull`/`if` produced executable SQL.
- The cumulative-PO delta is valid only while required dates are nondecreasing in allocation order. A priority sequence that moves backward in date needs per-PO-lot state, which the native reference handles explicitly.
- The emitted windows are global for this one-material/one-warehouse POC; multi-stream use requires explicit partitioning.

## Debugging experience

- The tiny base case made incorrect date/status handling immediately visible.
- Keeping the native implementation independent from the SQLazy workflow made the comparison more meaningful than duplicating one query under two names.
- Named NSPL intermediates made it easy to isolate runtime/compiler differences at the exact failing row.

## Generated SQL quality

- The real compiler query is executable and correct for the planned scope.
- It expands 20 NSPL steps into 12 CTEs and several window functions.
- Some output is mechanically verbose: conditional summaries become `FIRST_VALUE` plus `MAX`, and `LAG` expressions are repeated.
- The bounded NSPL running-min interval becomes `ROWS BETWEEN 1000000 PRECEDING AND CURRENT ROW`.

## Native SQL comparison

- The native implementation favors correctness and auditability over compactness: a PL/pgSQL function carries stock and JSONB PO-lot balances explicitly.
- SQLazy web runtime, SQLazy-compiled PostgreSQL, and the native implementation all produced `SO001=70/0/0`, `SO002=30/40/10`, and `SO003=0/50/10` for stock/PO/shortage, with total shortage 20.
- Performance was not benchmarked; the project plan marks it optional after correctness, so it remains outside this POC.

## Verdict

For the planned single-material/single-warehouse workload, SQLazy **passed the correctness POC**: its runtime result matched the expected CSV, its real PostgreSQL compiler output matched the independent native reference, and all three edge cases passed. It is not yet production-qualified because multi-stream partitioning, backward-moving dates under priority ordering, the finite running-min frame, and performance remain outside the verified scope.
