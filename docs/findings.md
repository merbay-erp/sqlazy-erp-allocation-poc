# Findings

## Confirmed outcomes

- The full five-table ERP model is implemented without changing the specified source columns.
- Official SQLazy web runtime output matched all seven expected rows.
- SQLazy's real POSTGRES compiler produced executable SQL.
- Compiler SQL, web output, expected CSV, and the independent native reference matched exactly.
- PostgreSQL 14.18 and 16.14 both passed the base verification and six edge scenarios.
- Material/warehouse partitions, production demand, transfer destinations, statuses, partial allocation, and backward-moving dates are explicitly tested.

## Design decisions

### Production priority

The supplied production schema has no priority column. The POC assigns confirmed production demand priority 3, after the sales priorities in the fixed case. This is declared in both implementations and tested.

### Unified supply adapter

The base source model remains unchanged. A read-only `supply_events_sqlazy` view maps:

- purchase order warehouse directly to `warehouse_id`;
- transfer `to_warehouse` to `warehouse_id`;
- both expected dates to `available_date`;
- a discriminator to `PURCHASE_ORDER` or `TRANSFER`.

This is a compiler compatibility boundary. It lets one SQLazy join attach both eligible supply types while later stages still enforce PO-before-transfer consumption.

### Running supply frontier

Cumulative eligible supply can fall when priority ordering moves required dates backward. Adjacent cumulative differences would then create negative “new supply.” The final workflow uses the maximum cumulative amount ever reached per stream and introduces only increases in that frontier. The native per-lot implementation and the date-reversal test independently verify the behavior.

## Observed SQLazy behavior

These are measured observations from the web app, with the current-syntax run repeated on 2026-08-27:

- Direct current-alias state expressions ran in the interpreter but the compiler rejected them.
- Numeric `nvl` generated PostgreSQL expressions comparing numbers with empty strings.
- A second join after an aggregate failed compilation with only `null` as the reported cause.
- Refactoring to window regulators, `isnull`/`if`, one supply join, and a supply frontier produced executable PostgreSQL.
- The direct trailing-condition migration was accepted but shifted each condition to the following aggregate, changing valid-looking seven-row results. The explicit seed workaround restored exact fixture semantics; see `COMPATIBILITY.md`.
- The preserved legacy compiler artifact is 753 lines / 20 CTEs; the current artifact is 772 lines / 20 CTEs.

## Remaining engineering boundary

The POC is correctness-complete for the stated challenge, but not production-certified.

- Running frames are finite at one million prior rows because SQLazy compiles the relative interval literally.
- No representative-volume benchmark has been run.
- Concurrent reservation/allocation transactions, isolation level, retries, and locking are outside this read-only calculation.
- Production deployments should decide whether the supply adapter is a view, materialized view, or maintained event table based on data volume and freshness requirements.

## Verdict

SQLazy passes the full correctness POC when the workflow is shaped around the observed runtime/compiler constraints. Its source representation is compact and reviewable; native PostgreSQL remains the more explicit control for lot-by-lot mutable state. Generated-SQL readability and plan-level optimization are not treated as SQLazy's primary goals, while independent correctness validation remains the test axis of this repository.
