# SQLazy ERP Allocation POC

A reproducible, evidence-driven ERP allocation case study built from the full five-table challenge—not a toy balance query.

It models time-phased demand and supply across materials and warehouses, executes the workflow in the official SQLazy web app, captures SQLazy's real PostgreSQL compiler output, and compares both against an independent native PostgreSQL implementation.

## Verified status

| Check | Result |
|---|---|
| Official SQLazy web runtime | 7/7 expected rows matched |
| SQLazy POSTGRES compiler | Generated 17,922 characters of executable SQL |
| Independent native reference | 7/7 expected rows matched |
| PostgreSQL 14.18 | Base case + 6 edge scenarios passed |
| PostgreSQL 16.14 | Base case + 6 edge scenarios passed |
| Conservation invariant | Passed on every row |
| Total base shortage | 25 |
| Multi-stream isolation | Passed |
| Priority/date reversal | Passed without negative or reused supply |

The captured web result, expected CSV, compiled SQL, and native output are compared bidirectionally by the test harness.

## The ERP problem

The source model is exactly:

- `stock(material_id, warehouse_id, qty_on_hand, qty_reserved)`
- `sales_orders(order_id, material_id, required_date, qty, priority, warehouse_id, status)`
- `purchase_orders(po_id, material_id, expected_date, qty, warehouse_id, status)`
- `production_orders(prod_id, material_id, required_date, qty, warehouse_id, status)`
- `transfers(transfer_id, material_id, from_warehouse, to_warehouse, expected_date, qty, status)`

For each material/warehouse stream, demand is allocated in deterministic priority/date/document order. Eligible supply is consumed once and in this order:

1. usable opening stock;
2. confirmed purchase orders available by the demand date;
3. confirmed transfers arriving at the destination warehouse by the demand date;
4. remaining uncovered quantity becomes shortage.

Confirmed production orders are additional demand. Because the supplied production schema has no priority column, the POC declares and tests a priority-3 policy.

## Architecture

```mermaid
flowchart LR
    A[Five ERP source tables] --> B[supply_events_sqlazy read-only adapter]
    A --> C[Independent native PL/pgSQL]
    B --> D[35-step SQLazy NSPL]
    D --> E[Official SQLazy runtime result]
    D --> F[SQLazy POSTGRES compiler]
    F --> G[PostgreSQL 14 and 16]
    C --> G
    H[Expected CSV] --> I[Bidirectional comparison + invariants]
    E --> I
    G --> I
```

The adapter exists because the SQLazy compiler rejected a second join after an aggregate. It does not replace or alter the five source tables; it presents POs and destination-normalized transfers as one read-only event stream so the NSPL needs only one supply join.

## Fixed result

| Material / warehouse | Demand | Type | Requested | Stock | PO | Transfer | Shortage | Projected |
|---|---|---|---:|---:|---:|---:|---:|---:|
| M100 / W1 | SO001 | Sales | 70 | 70 | 0 | 0 | 0 | 30 |
| M100 / W1 | SO002 | Sales | 80 | 30 | 40 | 0 | 10 | 0 |
| M100 / W1 | SO003 | Sales | 60 | 0 | 50 | 10 | 0 | 20 |
| M100 / W1 | PROD001 | Production | 25 | 0 | 0 | 20 | 5 | 0 |
| M200 / W2 | SO201 | Sales | 40 | 40 | 0 | 0 | 0 | 10 |
| M200 / W2 | SO202 | Sales | 30 | 10 | 10 | 5 | 5 | 0 |
| M200 / W2 | PROD201 | Production | 5 | 0 | 0 | 0 | 5 | 0 |

Every row satisfies:

```text
requested = from_stock + from_purchase_orders + from_transfers + shortage
```

Cancelled/draft `SO999`, `PO999`, `PROD999`, and `T999` are present in the input and contribute nothing.

## Run it

Requirements: Docker and Docker Compose.

```bash
make up
make verify
make down
```

`make verify` recreates the PostgreSQL schema, loads the fixed data, installs both implementations, compares all four result artifacts, checks invariants and supply caps, then executes six rolled-back edge scenarios:

- same-day priority;
- late PO and transfer;
- exact stock + PO + transfer balance;
- production priority plus multi-stream/transfer-destination isolation;
- priority ordering that moves required dates backward.
- a demand stream with no opening-stock row.

GitHub Actions runs the same PostgreSQL 16 verification on every push and pull request.

## Reproduce the SQLazy web run

1. Open [SQLazy](https://www.sqlazy.com/).
2. Add the CSV anchors in `sqlazy/input/`: `stock`, `sales_orders`, `production_orders`, and `supply_events_sqlazy`.
3. Enter/import `sqlazy/allocation.nspl`.
4. Run the final `allocation_result` step and compare it with `sqlazy/execution_result.csv`.
5. Select `POSTGRES`, compile the final step, and compare it with the query body in `sqlazy/generated_postgresql.sql`.

The base `purchase_orders` and `transfers` CSVs are also included so the adapter view can be independently reconstructed.

## Repository map

```text
.
├── .github/workflows/verify.yml
├── schema/                 # exact ERP tables, indexes, adapter view, seed
├── sqlazy/
│   ├── allocation.nspl     # 35 reviewable steps
│   ├── generated_postgresql.sql
│   ├── execution_result.csv
│   ├── execution-notes.md
│   └── input/              # web-app-ready CSV anchors
├── native/reference_postgresql.sql
├── expected/expected_result.csv
├── tests/
│   ├── verification.sql
│   ├── edge_cases.sql
│   └── edge_cases.md
└── docs/
    ├── requirements-coverage.md
    ├── comparison.md
    └── findings.md
```

## Measured comparison

| Artifact | Size | Role |
|---|---:|---|
| SQLazy NSPL | 35 lines / 4.4 KB | Reviewable business workflow |
| SQLazy-generated PostgreSQL | 753 lines / 18.1 KB / 20 CTEs | Executable compiler output |
| Native PostgreSQL reference | 213 lines / 7.1 KB | Independent per-lot control |

SQLazy is much shorter at the source level. Native PL/pgSQL is more explicit about mutable lot balances. The generated SQL is correct for the tested cases but mechanically verbose and uses finite one-million-row running frames.

See `docs/comparison.md` for the row-by-row and implementation comparison, and `docs/requirements-coverage.md` for full challenge coverage.

## Honest boundary

This is a correctness POC, not a production performance certification. It deliberately tests multiple streams, date eligibility, statuses, partial allocation, transfer destination, production demand, and backward-moving dates. It does not claim high-volume performance or replace concurrency/locking design required by a transactional ERP allocation service.

The source-table contract and business result are complete for the stated challenge. The SQLazy adapter and observed compiler limitations are documented rather than hidden.

## Version history

- `v1-core-poc`: original three-table core case.
- `v2-full-erp-case`: full five-table challenge with production, transfers, multi-stream partitioning, compiler adapter, and expanded tests.

## License

MIT. See `LICENSE`.
