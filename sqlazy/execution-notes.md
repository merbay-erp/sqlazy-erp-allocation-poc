# SQLazy execution notes

## Captured run

- Date: 2026-08-27
- Application: official SQLazy web app
- Dialect: `POSTGRES`
- Final workflow: 35 NSPL steps
- Compiler query body: 18,454 characters

The official runtime materialized all 35 named steps and returned the seven rows stored in `runtime/current-result.csv`. The final step was then compiled, and the captured query was wrapped only with:

```sql
CREATE OR REPLACE VIEW sqlazy_allocation_result AS
```

The resulting current file is `compiled/postgres-current.sql`. The previous 753-line output is preserved separately as `compiled/postgres-legacy.sql`.

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
7. Join supply once and conditionally summarize cumulative PO and transfer availability using the current trailing-condition syntax and the explicit binding seed described in `COMPATIBILITY.md`.
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
- The 2026-08-27 runtime/compiler applied a trailing condition to the following aggregate, not the preceding aggregate described in the release note. `compatibility_filter_seed` keeps the intended PO and transfer bindings; the isolated failure and workaround are documented in `COMPATIBILITY.md`.

## Verification

The current captured compiler SQL passed:

- the seven-row fixed result;
- bidirectional comparison with the web CSV, expected CSV, and native reference;
- conservation and non-negative invariants;
- stock, PO, and destination-transfer supply caps;
- six edge scenarios;
- PostgreSQL 14.18 and 16.14.

The current artifact is 772 lines / 20 CTEs, compared with the preserved legacy artifact at 753 lines / 20 CTEs. This measurement is compatibility evidence, not a performance claim.
