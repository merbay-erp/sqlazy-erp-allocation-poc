# SQLazy execution notes

## Captured run

- Date: 2026-08-27
- Application: official SQLazy web app
- Dialect: `POSTGRES`
- Final workflow: 35 NSPL steps
- Compiler query body: 17,970 characters

The official runtime materialized all 35 named steps and returned the seven rows stored in `runtime/current-result.csv`. The final step was then compiled, and the captured query was wrapped only with:

```sql
CREATE OR REPLACE VIEW sqlazy_allocation_result AS
```

The resulting fixed-runtime file is `compiled/postgres-current.sql`. The 772-line stale-web workaround output is preserved as `compiled/postgres-stale-web-workaround.sql`, and the original 753-line output remains `compiled/postgres-legacy.sql`.

## Web input anchors

Use these files from `sqlazy/input/`:

| Anchor | CSV |
|---|---|
| `stock` | `stock.csv` |
| `sales_orders` | `sales_orders.csv` |
| `production_orders` | `production_orders.csv` |
| `supply_events_sqlazy` | `supply_events_sqlazy.csv` |

The base purchase-order and transfer CSVs are included separately to reconstruct the adapter event stream.

## Workflow outline

1. Normalize usable stock.
2. Filter and normalize sales demand.
3. Filter and normalize production demand with priority 3.
4. Concatenate and deterministically order demand.
5. Join stock by material/warehouse.
6. Filter the unified incoming-supply event stream.
7. Join supply once and conditionally summarize cumulative PO and transfer availability using the natural current trailing-condition syntax.
8. Re-sort demand and calculate the running maximum supply frontier.
9. Introduce only frontier increases as new PO/transfer supply.
10. Allocate stock, then PO, then transfer through partitioned balance regulators.
11. Return the exact eleven requested columns.

## Why an adapter view is present

The interpreter accepted a second join after an aggregate, but the POSTGRES compiler returned `When compiling row 14, error: null`. Renaming the transfer key in a prior `derive` or `compute` step did not change the result.

The final solution uses `supply_events_sqlazy`, a read-only `UNION ALL` view over the exact purchase-order and transfer tables. This removes the second join while preserving the required supply type and destination semantics.

## Other observed compiler adjustments

- A previous-row current-alias formulation ran but did not compile.
- Numeric `nvl` emitted invalid number/empty-string comparisons in PostgreSQL.
- `isnull`/`if` and cumulative running-min regulators compiled successfully.
- Stateful windows are explicitly partitioned by `stream_key = material_id | warehouse_id`.
- Running max/min expressions use `[-1000000:0]`, which compiles to a finite one-million-row frame.
- An initially stale web jar applied a trailing condition to the following aggregate. SQLazy synchronized the web runtime to the fixed build, which correctly binds to the preceding aggregate; the temporary `compatibility_filter_seed` was removed. The incident and preserved workaround artifact are documented in `COMPATIBILITY.md`.

## Verification

The current captured compiler SQL passed:

- the seven-row fixed result;
- bidirectional comparison with the web CSV, expected CSV, and native reference;
- conservation and non-negative invariants;
- stock, PO, and destination-transfer supply caps;
- six edge scenarios;
- PostgreSQL 14.18 and 16.14.

The fixed-runtime artifact is 757 lines / 20 CTEs. The preserved stale-web workaround artifact is 772 lines / 20 CTEs, and the legacy artifact is 753 lines / 20 CTEs. These measurements are compatibility evidence, not a performance claim.
