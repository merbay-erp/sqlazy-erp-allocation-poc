# SQLazy execution notes

## Capability review

The public SQLazy knowledge base documents actions for filtering, sorting, joining, computing columns, summarizing, deriving projections, and cross-row calculations. This workflow uses `if`, postfix `isnull`, cumulative `compute`, relative-row references such as `field[-1]`, and a bounded running-min interval.

## Business decomposition

1. Calculate usable opening stock.
2. Keep only open demand and order it deterministically.
3. Keep only confirmed POs and calculate supply eligible by each required date.
4. Turn cumulative PO eligibility into newly available supply.
5. Derive stock consumption from cumulative demand.
6. Derive PO balance and shortage from cumulative net supply and its running minimum.
7. Project allocations, shortage, and remaining balances.

## Action matching

| Need | SQLazy action/function |
|---|---|
| Normalize stock | `compute` |
| Filter statuses | `filter` |
| Stable demand sequence | `sort` |
| Attach stock and PO rows | `join` |
| PO supply eligible by date | conditional `summarize` |
| Cumulative demand and net PO flow | `compute ... cum` |
| Previous-row delta | `compute` with `field[-1]`, `if`, and `isnull` |
| Running shortage regulator | `compute min` over a relative interval |
| Final columns | `derive` |

## Compiler provenance

On 2026-08-25 `allocation.nspl` was imported into the official SQLazy web app. The `stock`, `sales_orders`, and `purchase_orders` anchors were populated with the fixed CSV data, the full workflow was executed, and `allocation_result` returned the three expected rows. The captured web result is stored in `execution_result.csv`.

The target dialect was then set to `POSTGRES` and the final step was compiled. `generated_postgresql.sql` contains that compiler-produced query. The only manual addition is the leading `CREATE OR REPLACE VIEW sqlazy_allocation_result AS` wrapper and provenance comments required by the repeatable SQL test harness.

The wrapped compiler query passed the complete verification suite in a fresh local PostgreSQL 14.18 database and in the Docker Compose PostgreSQL 16 service.

The first stateful formulation executed in SQLazy but the compiler rejected a current-alias reference in row 10 (`stock_remaining`). The final formulation replaces recursive aliases with cumulative demand and a running-min regulator. A second compiler-specific adjustment replaced numeric `nvl` calls with `isnull`/`if`, avoiding generated `NULLIF(number, '')` expressions. These are observed compiler behaviors, not hypothetical limitations.

## Reproduction procedure

1. Configure the three input tables in the SQLazy IDE or web app.
2. Import `allocation.nspl`.
3. Execute the workflow and compare `allocation_result` with `execution_result.csv`.
4. Select `POSTGRES`, compile the final step, and compare the query with the body of `generated_postgresql.sql`.
5. Run `make verify`.

## Known abstraction risk

The NSPL computes newly eligible PO supply as the difference between cumulative PO availability in adjacent demand rows. This is correct for the fixed dataset and the three scoped edge cases because required dates are nondecreasing in allocation order. If priority ordering makes required dates move backwards, remaining PO lots must be tracked by expected date; the native reference function already does this, but the current NSPL does not.

The POC has one material/warehouse stream. The emitted window functions are global and require explicit partitioning before a multi-stream production use case. The running minimum is compiled from `po_net_cumulative[-1000000:0]`, so its frame is finite at one million preceding rows.
