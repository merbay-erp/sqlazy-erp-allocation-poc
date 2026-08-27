# Full ERP challenge coverage

This matrix maps every requirement in the public ERP allocation challenge to executable evidence in this repository.

| Requirement | Implementation | Evidence |
|---|---|---|
| Five ERP source tables | Exact PostgreSQL tables for stock, sales orders, purchase orders, production orders, and transfers | `schema/01_schema.sql` |
| Usable opening stock | `qty_on_hand - qty_reserved` | NSPL step 1 and native reference |
| Sales order status | Only `OPEN` contributes demand | Base data includes cancelled `SO999` |
| Sales ordering | Priority, required date, document ID | NSPL demand sort and native loop order |
| Production as demand | Confirmed production is unioned with sales demand | `PROD001`, `PROD201`, and draft `PROD999` |
| Production priority policy | Production uses priority 3 because the supplied schema has no production priority column | NSPL/native demand normalization |
| Purchase availability | Confirmed POs become eligible only when `expected_date <= required_date` | Conditional supply summary and late-supply edge test |
| Transfer destination/date | Confirmed transfers use `to_warehouse` and arrival date | Adapter view, native reference, destination-isolation test |
| Supply precedence | Opening stock, then PO, then transfer | Separate sequential regulators |
| Progressive consumption | Allocation is partitioned by material/warehouse and supply is introduced once | Running supply frontier and balance regulators |
| No reuse | Previously introduced/consumed supply cannot reappear when priority moves dates backward | Priority/date-reversal edge test |
| Partial allocation | Every source can cover part of one demand | SO002, SO003, PROD001, SO202 |
| Shortage | Remaining uncovered demand is explicit | Total base shortage = 25 |
| Projected balance | Remaining eligible stock + PO + transfer after each row | Final output and expected CSV |
| Multiple streams | All stateful windows partition by material/warehouse stream | M100/W1 and M200/W2 base data |
| Exact requested output | Eleven named output columns | Expected, web, compiler, and native result tables |
| Independent control | PL/pgSQL tracks stock and individual PO/transfer lots | `native/reference_postgresql.sql` |
| Real SQLazy evidence | Current official web runtime and POSTGRES compiler output are captured without overwriting the legacy artifacts | `sqlazy/runtime/current-result.csv`, `sqlazy/compiled/postgres-current.sql`, `sqlazy/compiled/postgres-legacy.sql` |
| Syntax regression | Deprecated prefix-form conditional aggregates cannot return unnoticed | `scripts/check_sqlazy_syntax.py`, CI syntax job |
| Reproducibility | Exact Docker PostgreSQL 14.18/16.14 matrix plus GitHub Actions | `Makefile`, `docker-compose.yml`, CI workflow |

## Compiler adapter

The five source tables remain exactly as specified. SQLazy's PostgreSQL compiler returned a null error when the workflow attempted a second join after an aggregate. The repository therefore exposes purchase orders and destination-normalized transfers through the read-only `supply_events_sqlazy` view, allowing one supply join. Purchase and transfer quantities remain separate through `supply_type` and are consumed in the required order.

This is an explicit, tested adapter—not a hidden change to the business rules.
