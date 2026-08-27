# SQLazy vs native PostgreSQL

## Row-by-row result

The fixed dataset was rerun in the official SQLazy web app on 2026-08-27 with the current trailing-condition syntax. The final runtime table was captured in `sqlazy/runtime/current-result.csv`. SQLazy's current POSTGRES compiler output and the independent native implementation were then run in PostgreSQL 14.18 and 16.14.

| Demand | Expected stock / PO / transfer / shortage | SQLazy web | Compiled PostgreSQL | Native PostgreSQL |
|---|---:|---:|---:|---:|
| SO001 | 70 / 0 / 0 / 0 | Match | Match | Match |
| SO002 | 30 / 40 / 0 / 10 | Match | Match | Match |
| SO003 | 0 / 50 / 10 / 0 | Match | Match | Match |
| PROD001 | 0 / 0 / 20 / 5 | Match | Match | Match |
| SO201 | 40 / 0 / 0 / 0 | Match | Match | Match |
| SO202 | 10 / 10 / 5 / 5 | Match | Match | Match |
| PROD201 | 0 / 0 / 0 / 5 | Match | Match | Match |

Total shortage is 25. All seven rows satisfy conservation and non-negative allocation invariants.

## Implementation comparison

| Dimension | SQLazy | Native PostgreSQL |
|---|---|---|
| Source form | 35 declarative NSPL steps | PL/pgSQL function + view |
| Source size | 35 lines / 4.4 KB | 213 lines / 7.1 KB |
| Database form | 757 fixed-runtime lines, 20 CTEs; 772-line stale-workaround and 753-line legacy artifacts retained | Procedural function returning rows |
| Demand state | Partitioned windows per material/warehouse | Ordered loop with stream reset |
| PO/transfer state | Running availability frontier + shortage regulators | JSONB balance per individual lot |
| Supply precedence | Separate stock, PO, and transfer stages | Explicit sequential mutation |
| Auditability | Named intermediate business stages | Exact lot consumption is visible |
| Portability | Compiler can target dialects | PostgreSQL-specific |
| Compiler adapter | Read-only unified supply-event view | Not required |
| Verified result | Web + PostgreSQL 14/16 | PostgreSQL 14/16 |

## Why the supply frontier matters

A simple adjacent difference of cumulative eligible supply fails if business priority moves required dates backward. Example:

1. priority-1 demand dated October 10 sees a PO and consumes it;
2. priority-2 demand dated October 1 must not make that PO “disappear” as negative supply;
3. a later row must not reintroduce the same PO.

The final NSPL carries the maximum cumulative eligible supply reached so far per material/warehouse. Only an increase in that frontier becomes new supply. The fifth edge scenario proves the compiled SQL matches the native per-lot reference and never emits a negative allocation.

## Test matrix

| Scenario | Main risk | Result |
|---|---|---|
| Fixed two-stream ERP case | Full rule interaction | Passed |
| Same-day priority | Unstable demand ordering | Passed |
| Late PO + transfer | Future supply used retroactively | Passed |
| Exact mixed balance | Partial allocation arithmetic | Passed |
| Production + destination isolation | Cross-stream or wrong-warehouse leakage | Passed |
| Priority/date reversal | Negative or reused incoming supply | Passed |
| Missing stock row | Demand silently dropped by an inner join | Passed |
| Cancelled/draft rows | Invalid status contributes demand/supply | Passed |

## Where SQLazy helped

- The 35 business stages remain substantially shorter than the emitted SQL.
- Named intermediates made failures traceable to one workflow row.
- Partitioned cumulative operations express progressive state without recursive SQL.
- The runtime and compiler can be independently checked against the same expected data.

## Where the abstraction leaked

- A direct current-alias formulation ran but did not compile.
- Numeric `nvl` emitted invalid PostgreSQL comparisons to empty strings; `isnull`/`if` was required.
- A second join after an aggregate caused the compiler to return only a null error. The read-only supply adapter avoids that compiler path.
- A stale web jar once shifted trailing filters to the following aggregate. The updated runtime binds to the preceding aggregate correctly; the removed workaround and its artifact remain documented for history.
- Relative running windows compile as `1000000 PRECEDING`, not true unbounded frames.
- Generated SQL is much larger than both the NSPL and native control.

## Performance interpretation

No throughput claim is made from seven rows. Tiny-data timings would measure startup and PL/pgSQL overhead rather than allocation scalability. A production decision needs representative volume, indexes, concurrent allocation semantics, and query-plan/lock analysis.

SQLazy's team clarified that generated-SQL readability and execution-plan optimization are not primary product goals. For this POC, emitted SQL is retained as compatibility evidence, correctness is measured, and performance qualification is intentionally not inferred.
