# Current SQLazy compatibility notes

## Test target

- Date: 2026-08-27
- Product surface: official SQLazy web runtime and `POSTGRES` compiler
- Reference syntax example: <https://www.sqlazy.com/?3OH>
- Workflow: all 35 steps in `sqlazy/allocation.nspl`

## Conditional aggregate migration

The deprecated prefix form was removed:

```text
condition (...) sum supply_qty as cumulative_po
```

The current grammar places the condition after a named aggregate:

```text
sum supply_qty as cumulative_po, condition (...)
```

`scripts/check_sqlazy_syntax.py` scans every `.nspl` file and fails CI if a prefix-form conditional sum returns. It also rejects a trailing `condition` that is not immediately preceded by a named `sum` clause.

## Observed trailing-condition binding defect

The current release accepts the new syntax, but the tested runtime/compiler binding does not match the announced semantics. With the direct migration:

```text
sum supply_qty as cumulative_po,
condition (supply_type="PURCHASE_ORDER" && available_date<=required_date),
sum supply_qty as cumulative_transfer,
condition (supply_type="TRANSFER" && available_date<=required_date)
```

the official runtime produced this mapping:

| Output aggregate | Expected filter | Observed filter |
|---|---|---|
| `cumulative_po` | purchase order + available date | none; all joined supply was summed |
| `cumulative_transfer` | transfer + available date | purchase order + available date |
| final trailing condition | binds to `cumulative_transfer` | omitted because no aggregate followed it |

That shifted future supply into earlier demands. For example, SO001's projected balance became 150 instead of 30. The run still returned seven rows, so a compile-only or row-count-only test would not have caught the regression.

## Explicit workaround

The POC inserts one visible, unused aggregate before the first condition:

```text
sum supply_qty as compatibility_filter_seed,
condition (supply_type="PURCHASE_ORDER" && available_date<=required_date),
sum supply_qty as cumulative_po,
condition (supply_type="TRANSFER" && available_date<=required_date),
sum supply_qty as cumulative_transfer
```

Under the observed binding, the first condition now filters `cumulative_po` and the second filters `cumulative_transfer`. `compatibility_filter_seed` is propagated by the generated SQL but is never used by the allocation logic and is excluded from the final eleven-column result.

This workaround must not be removed silently. When SQLazy corrects the runtime/compiler to bind a condition to the preceding aggregate, this line should fail the fixture comparison and be revisited against the then-current release.

## Evidence after the workaround

| Check | Evidence |
|---|---|
| Current web runtime | 35/35 named steps materialized without an error |
| Main result | 7/7 rows match `expected/expected_result.csv` exactly |
| Edge scenarios | All 6 pass against compiled and native implementations |
| PostgreSQL | Exact server versions 14.18 and 16.14 pass |
| Native reference | Unchanged SHA-256: `c7c237af0610196a59c899a94c5464d3afc5ec30076964e057215abe47bf32d6` |
| Legacy compiler artifact | 753 lines / 20 CTEs |
| Current compiler artifact | 772 lines / 20 CTEs |
| Deprecated prefix syntax | 0 occurrences |

The 19-line increase is recorded only as compatibility evidence. Generated-SQL readability and execution-plan optimization are not treated as SQLazy's primary goals; the relevant POC claim remains correctness against the fixed CSV and independent native control.

## Running-frontier design

The allocation does not perform interval/round propagation. It makes one ordered pass per material/warehouse stream, carries the maximum cumulative eligible supply frontier, and introduces only increases as new PO or transfer supply. This remains stable when a higher-priority demand has a later required date than the following row.

SQLazy's team reported as external feedback that their interval-based attempt required additional propagation rounds as the supply/demand structure grew and became fragile. That observation independently supports this POC's running-frontier choice; it is not presented as a benchmark or product guarantee.
