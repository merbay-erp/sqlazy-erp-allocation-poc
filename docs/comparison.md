# SQLazy and native PostgreSQL comparison

## Measured result

The fixed dataset was executed in the official SQLazy web app on 2026-08-25. The final `allocation_result` table was exported to `sqlazy/execution_result.csv`. The same compiler-produced query and the independent native implementation were then executed in a fresh PostgreSQL 14.18 database and in the Dockerized PostgreSQL 16 target.

| Order | Expected stock/PO/shortage | SQLazy web runtime | SQLazy-compiled PostgreSQL | Native PostgreSQL | Result |
|---|---:|---:|---:|---:|---|
| SO001 | 70 / 0 / 0 | 70 / 0 / 0 | 70 / 0 / 0 | 70 / 0 / 0 | Match |
| SO002 | 30 / 40 / 10 | 30 / 40 / 10 | 30 / 40 / 10 | 30 / 40 / 10 | Match |
| SO003 | 0 / 50 / 10 | 0 / 50 / 10 | 0 / 50 / 10 | 0 / 50 / 10 | Match |

Total requested demand is 210, usable opening stock is 100, confirmed PO supply eligible through the last demand date is 90, and total shortage is 20. The per-row conservation invariant also passed for both database implementations.

## Implementation comparison

| Dimension | SQLazy | Native PostgreSQL |
|---|---|---|
| Source form | 20 declarative NSPL steps | PL/pgSQL function plus a view |
| Progressive stock | Cumulative demand and window expressions | Mutable balance in ordered loop |
| Progressive PO supply | Cumulative eligibility plus a running-min regulator | Explicit remaining quantity per PO lot in JSONB |
| Generated database form | 12 CTEs with window functions | Procedural function returning rows |
| Auditability | Business stages are visible in named intermediate tables | Each allocation mutation is explicit in one function |
| Portability | Compiler emits target-specific SQL | Written directly for PostgreSQL |
| Verified scope | Fixed dataset and the three planned edge cases | Fixed dataset and the same three edge cases |

## Verification outcomes

- Fixed expected rows: passed.
- SQLazy web runtime versus expected CSV: matched all three rows.
- SQLazy compiler output versus native reference: passed with no row differences.
- Same-day priority: passed.
- Late purchase: passed.
- Exact balance: passed.
- Cancelled demand and draft PO exclusion: passed.
- No stock or PO over-allocation: passed.

## Quality observations

SQLazy made the business decomposition concise and inspectable. Its generated PostgreSQL is substantially more verbose than the NSPL source: it expands summaries into `FIRST_VALUE` plus `MAX`, repeats some `LAG` expressions, and implements progressive availability through several windowed CTEs. The native function is more direct for per-lot state and remains the clearer control implementation.

The POC intentionally contains one material and one warehouse. The generated windows are global, and the NSPL derives newly eligible supply from adjacent cumulative totals. A production extension to multiple material/warehouse streams or to priority ordering that moves required dates backward must add explicit partitions and per-PO-lot eligibility handling. The compiler also renders the running minimum as a finite `1000000 PRECEDING` frame because the NSPL uses a bounded relative interval. These are recorded scope limits, not claims of production readiness.

No performance benchmark was run; the project plan makes benchmarking optional until correctness is established.

## Project-plan compliance

| Plan requirement | Evidence | Status |
|---|---|---|
| Tiny reproducible allocation POC | Fixed M100/W1 dataset and deterministic rules in `README.md` | Complete |
| Required repository structure | Schema, seed, NSPL, compiler SQL, native SQL, expected CSV, tests, findings, Docker, Makefile, and license are present | Complete |
| Exact fixed result | All three rows match the project-plan table | Complete |
| Real SQLazy execution | Captured in `sqlazy/execution_result.csv` and checked by `tests/verification.sql` | Complete |
| Real PostgreSQL compiler output | Preserved in `sqlazy/generated_postgresql.sql` with only a test-view wrapper | Complete |
| Independent native reference | `native/reference_postgresql.sql` tracks stock and PO-lot balances separately | Complete |
| Expected/native/compiler comparison | Bidirectional `EXCEPT` assertions plus the table above | Complete |
| Three requested edge cases | Same-day priority, late purchase, and exact balance all pass | Complete |
| Fresh reproducible database | Verified locally and with `make up && make verify`; container removed with `make down` | Complete |
| Evidence-based findings | Runtime/compiler issues and verified scope limits are recorded in `docs/findings.md` | Complete |
| Optional benchmark | Not performed, as permitted by the plan | Not required |
