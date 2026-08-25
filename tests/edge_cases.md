# Edge-case verification

`tests/edge_cases.sql` executes each scenario in a transaction and rolls it back.

| Scenario | Setup | Assertion |
|---|---|---|
| Same-day priority | Two sales demands compete for 50 stock | Priority 1 receives 40; priority 2 receives the remaining 10 |
| Late supply | PO and transfer arrive one day after demand | Neither covers the earlier demand |
| Exact mixed balance | Stock 5 + PO 3 + transfer 2 covers demand 10 | All three sources allocate exactly; shortage/projected balance are zero |
| Production and destination isolation | Two warehouses share a material; transfer targets only W2 | W1 production cannot consume W2 transfer; state does not leak between streams |
| Priority/date reversal | Higher priority is dated later than lower priority | PO is introduced once, no negative allocation appears, compiler equals native |
| Missing stock row | Demand has no matching opening-stock record | Demand remains visible, opening stock is zero, eligible PO still allocates |

Every scenario compares all eleven output columns bidirectionally between SQLazy-generated PostgreSQL and the independent native implementation.
