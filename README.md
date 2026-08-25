# SQLazy ERP Allocation POC

A deliberately small, reproducible ERP stock-allocation case study. It compares a step-by-step SQLazy NSPL workflow with an independent native PostgreSQL reference implementation.

## Status

- The fixed dataset was executed in the official SQLazy web app on 2026-08-25 and matched the expected result exactly.
- `sqlazy/generated_postgresql.sql` contains the real `POSTGRES` compiler output; only a `CREATE VIEW` line was added so the test harness can load it repeatedly.
- The compiler output, independent native PostgreSQL reference, expected CSV, invariants, and all three planned edge cases passed in both a fresh local PostgreSQL 14.18 database and the Dockerized PostgreSQL 16 target.
- `make up`, `make verify`, and `make down` were executed successfully end to end.

## Problem

A warehouse begins with on-hand stock minus reservations. Open sales orders consume that stock in deterministic priority/date/order order. Confirmed purchase orders can be consumed only on or after their expected date. Supply is consumed once, partial allocation is allowed, and the uncovered part of each demand becomes shortage.

## Why this case?

The case combines filtering, stable ordering, date-sensitive availability, partial allocation, and state propagation. The fixed input is small enough to verify by hand but still exposes double-consumption and late-supply errors.

## Business rules

1. `usable_stock = qty_on_hand - qty_reserved`.
2. Only `OPEN` sales orders are demand.
3. Only `CONFIRMED` purchase orders are incoming supply.
4. Demand order is `priority ASC, required_date ASC, order_id ASC`.
5. A purchase order cannot cover a demand dated before `expected_date`.
6. Opening stock is consumed before incoming purchase supply.
7. Allocation is progressive; consumed supply cannot be reused.
8. Partial allocation is allowed and uncovered quantity becomes shortage.
9. Every row satisfies `allocated_stock + allocated_po + shortage = requested_qty`.

## Fixed dataset

Opening stock:

| material | warehouse | on hand | reserved | usable |
|---|---|---:|---:|---:|
| M100 | W1 | 120 | 20 | 100 |

Sales orders:

| order | required date | qty | priority | status |
|---|---|---:|---:|---|
| SO001 | 2026-09-01 | 70 | 1 | OPEN |
| SO002 | 2026-09-03 | 80 | 2 | OPEN |
| SO003 | 2026-09-05 | 60 | 2 | OPEN |
| SO999 | 2026-09-02 | 999 | 1 | CANCELLED |

Purchase orders:

| PO | expected date | qty | status |
|---|---|---:|---|
| PO101 | 2026-09-02 | 40 | CONFIRMED |
| PO102 | 2026-09-04 | 50 | CONFIRMED |
| PO999 | 2026-09-01 | 500 | DRAFT |

## Expected result

| order | requested | from stock | from PO | shortage |
|---|---:|---:|---:|---:|
| SO001 | 70 | 70 | 0 | 0 |
| SO002 | 80 | 30 | 40 | 10 |
| SO003 | 60 | 0 | 50 | 10 |

Valid demand is 210 and valid supply through 2026-09-05 is 190, so cumulative shortage is 20.

## Repository map

```text
.
├── README.md
├── LICENSE
├── docker-compose.yml
├── Makefile
├── schema/
│   ├── 01_schema.sql
│   └── 02_seed.sql
├── sqlazy/
│   ├── allocation.nspl
│   ├── generated_postgresql.sql
│   ├── execution_result.csv
│   └── execution-notes.md
├── native/
│   └── reference_postgresql.sql
├── expected/
│   └── expected_result.csv
├── tests/
│   ├── verification.sql
│   ├── edge_cases.sql
│   └── edge_cases.md
└── docs/
    ├── comparison.md
    └── findings.md
```

## Run the verification

Requirements: Docker with Compose.

```bash
make up
make verify
```

`make verify` recreates the POC tables inside the dedicated Docker database, loads the fixed data, creates both implementations, checks the expected rows and invariants, and executes the three scoped edge cases.

To stop the database:

```bash
make down
```

## SQLazy implementation

The reviewable workflow is in [`sqlazy/allocation.nspl`](sqlazy/allocation.nspl). It normalizes stock, filters and orders demand, calculates newly eligible purchase supply, and derives progressive balances with cumulative and running-min computations.

The NSPL file can be opened in the SQLazy IDE/web app with `stock`, `sales_orders`, and `purchase_orders` configured as table anchors. The measured web result is preserved in [`sqlazy/execution_result.csv`](sqlazy/execution_result.csv), and compiler provenance is recorded in [`sqlazy/execution-notes.md`](sqlazy/execution-notes.md).

## Verification

[`tests/verification.sql`](tests/verification.sql) checks:

- all three expected rows;
- exclusion of `SO999` and `PO999`;
- the per-row conservation invariant;
- total shortage of 20;
- no over-allocation of stock or confirmed POs;
- equality between the real SQLazy compiler output and the native reference result.

[`tests/edge_cases.sql`](tests/edge_cases.sql) runs same-day priority, late-purchase, and exact-balance cases in rolled-back transactions.

The measured side-by-side comparison is in [`docs/comparison.md`](docs/comparison.md).

## Conclusion

Within the planned single-material/single-warehouse POC, SQLazy passed the correctness evaluation and produced executable PostgreSQL. Its 20-step NSPL workflow is concise and reviewable, while the generated query is verbose and window-heavy. The native PL/pgSQL reference remains clearer for explicit per-PO-lot state. Multi-stream partitioning, backward-moving required dates under priority ordering, and performance are documented follow-up concerns rather than validated production capabilities.

## Sources

- [SQLazy official repository](https://github.com/SPLWare/SQLazy)
- [SQLazy web app](https://www.sqlazy.com/)
