# Edge cases

Only the three cases in the project plan are included.

1. **Same-day priority** — two orders share a required date; the lower priority number consumes stock first.
2. **Late purchase** — a PO expected one day after demand contributes zero to that demand.
3. **Exact balance** — opening stock plus eligible PO supply exactly equals demand, producing zero shortage and no negative balances.

Run them with `make verify`. Each case runs in its own transaction and rolls back, so the fixed verification dataset is left unchanged.

