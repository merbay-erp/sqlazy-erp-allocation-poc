# Current SQLazy compatibility notes

## Test target

- Date: 2026-08-27
- Product surface: official SQLazy web runtime and `POSTGRES` compiler
- Reference syntax example: <https://www.sqlazy.com/?3OH>
- Workflow: all 35 steps in `sqlazy/allocation.nspl`

## Current status

The updated web runtime implements the documented trailing-condition semantics: a condition binds to the preceding named aggregate. The current workflow therefore uses the natural form with no compatibility seed:

```text
sum supply_qty as cumulative_po,
condition (supply_type="PURCHASE_ORDER" && available_date<=required_date),
sum supply_qty as cumulative_transfer,
condition (supply_type="TRANSFER" && available_date<=required_date)
```

The web interpreter and `POSTGRES` compiler both apply the purchase-order condition to `cumulative_po` and the transfer condition to `cumulative_transfer`.

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

## Historical stale web-runtime incident

### Observed behavior

During the first current-syntax migration, the web runtime and compiler accepted the trailing form but bound each condition to the following aggregate. The direct migration produced this mapping:

```text
sum supply_qty as cumulative_po,
condition (supply_type="PURCHASE_ORDER" && available_date<=required_date),
sum supply_qty as cumulative_transfer,
condition (supply_type="TRANSFER" && available_date<=required_date)
```

the official runtime produced this mapping:

| Output aggregate | Expected filter | Stale runtime behavior |
|---|---|---|
| `cumulative_po` | purchase order + available date | none; all joined supply was summed |
| `cumulative_transfer` | transfer + available date | purchase order + available date |
| final trailing condition | binds to `cumulative_transfer` | omitted because no aggregate followed it |

That introduced future supply too early: SO001's projected balance became 150 instead of 30 even though the workflow still returned seven rows.

### Root cause

SQLazy confirmed that the web application was running a stale jar maintained by a separate team. The locally verified/current build already implemented preceding-aggregate binding correctly, but the web jar had not been synchronized. The web runtime was subsequently updated to that fixed build.

### Removed workaround

The temporary workaround inserted an unused aggregate before the shifted conditions:

```text
sum supply_qty as compatibility_filter_seed,
condition (supply_type="PURCHASE_ORDER" && available_date<=required_date),
sum supply_qty as cumulative_po,
condition (supply_type="TRANSFER" && available_date<=required_date),
sum supply_qty as cumulative_transfer
```

That workaround was valid only for the stale next-aggregate binding. On the fixed runtime it backfired: `cumulative_po` received the transfer filter and `cumulative_transfer` became unfiltered, reproducing the reported 120/30-across-the-board pattern. It has been removed from current code. The generated artifact from that historical run remains available as `sqlazy/compiled/postgres-stale-web-workaround.sql`; `sqlazy/compiled/postgres-legacy.sql` is also retained.

## Evidence after the fixed web runtime

The `demand_supply` intermediate now contains the intended cumulative eligibility values:

| Demand | `cumulative_po` | `cumulative_transfer` |
|---|---:|---:|
| SO001 | 0 | 0 |
| SO002 | 40 | 0 |
| SO003 | 90 | 30 |
| PROD001 | 90 | 30 |
| SO201 | 0 | 0 |
| SO202 | 10 | 5 |
| PROD201 | 10 | 5 |

The web table renders a blank cell where no eligible supply exists; downstream logic treats that state as zero. The stale across-the-board values are absent.

| Check | Evidence |
|---|---|
| Updated web runtime | 35/35 named steps materialized without an error |
| Main result | 7/7 rows match `expected/expected_result.csv` exactly |
| SO001 projected balance | 30 |
| Edge scenarios | All 6 pass against compiled and native implementations |
| PostgreSQL | Exact server versions 14.18 and 16.14 pass |
| Native reference | Unchanged SHA-256: `c7c237af0610196a59c899a94c5464d3afc5ec30076964e057215abe47bf32d6` |
| Legacy compiler artifact | 753 lines / 20 CTEs |
| Stale-web workaround artifact | 772 lines / 20 CTEs |
| Fixed-runtime current artifact | 757 lines / 20 CTEs |
| Deprecated prefix syntax | 0 occurrences |

The artifact sizes are compatibility evidence only. Generated-SQL readability and execution-plan optimization are not treated as SQLazy's primary goals; the relevant POC claim remains correctness against the fixed CSV and independent native control.

## Running-frontier design

The allocation does not perform interval/round propagation. It makes one ordered pass per material/warehouse stream, carries the maximum cumulative eligible supply frontier, and introduces only increases as new PO or transfer supply. This remains stable when a higher-priority demand has a later required date than the following row.

SQLazy's team reported as external feedback that their interval-based attempt required additional propagation rounds as the supply/demand structure grew and became fragile. That observation independently supports this POC's running-frontier choice; it is not presented as a benchmark or product guarantee.
