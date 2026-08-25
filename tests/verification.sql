CREATE TEMP TABLE expected_result (
    order_id text PRIMARY KEY,
    requested_qty bigint NOT NULL,
    allocated_stock bigint NOT NULL,
    allocated_po bigint NOT NULL,
    shortage bigint NOT NULL
);

\copy expected_result FROM 'expected/expected_result.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE sqlazy_web_result (
    order_id text PRIMARY KEY,
    material_id text NOT NULL,
    warehouse_id text NOT NULL,
    required_date date NOT NULL,
    priority integer NOT NULL,
    requested_qty bigint NOT NULL,
    allocated_stock bigint NOT NULL,
    allocated_po bigint NOT NULL,
    shortage bigint NOT NULL,
    stock_remaining bigint NOT NULL,
    po_remaining bigint NOT NULL
);

\copy sqlazy_web_result FROM 'sqlazy/execution_result.csv' WITH (FORMAT csv, HEADER true)

DO $$
BEGIN
    IF EXISTS (
        (
            SELECT order_id, requested_qty, allocated_stock, allocated_po, shortage
            FROM sqlazy_web_result
            EXCEPT
            SELECT order_id, requested_qty, allocated_stock, allocated_po, shortage
            FROM expected_result
        )
        UNION ALL
        (
            SELECT order_id, requested_qty, allocated_stock, allocated_po, shortage
            FROM expected_result
            EXCEPT
            SELECT order_id, requested_qty, allocated_stock, allocated_po, shortage
            FROM sqlazy_web_result
        )
    ) THEN
        RAISE EXCEPTION 'captured SQLazy web result does not match expected_result.csv';
    END IF;

    IF EXISTS (
        (
            SELECT order_id, requested_qty, allocated_stock, allocated_po, shortage
            FROM native_allocation_result
            EXCEPT
            SELECT order_id, requested_qty, allocated_stock, allocated_po, shortage
            FROM expected_result
        )
        UNION ALL
        (
            SELECT order_id, requested_qty, allocated_stock, allocated_po, shortage
            FROM expected_result
            EXCEPT
            SELECT order_id, requested_qty, allocated_stock, allocated_po, shortage
            FROM native_allocation_result
        )
    ) THEN
        RAISE EXCEPTION 'native allocation does not match expected_result.csv';
    END IF;

    IF EXISTS (
        (
            SELECT order_id, requested_qty, allocated_stock, allocated_po, shortage
            FROM sqlazy_allocation_result
            EXCEPT
            SELECT order_id, requested_qty, allocated_stock, allocated_po, shortage
            FROM native_allocation_result
        )
        UNION ALL
        (
            SELECT order_id, requested_qty, allocated_stock, allocated_po, shortage
            FROM native_allocation_result
            EXCEPT
            SELECT order_id, requested_qty, allocated_stock, allocated_po, shortage
            FROM sqlazy_allocation_result
        )
    ) THEN
        RAISE EXCEPTION 'SQLazy compiler output and native results differ';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM native_allocation_result
        WHERE requested_qty <> allocated_stock + allocated_po + shortage
    ) THEN
        RAISE EXCEPTION 'per-row conservation invariant failed';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM sqlazy_allocation_result
        WHERE requested_qty <> allocated_stock + allocated_po + shortage
    ) THEN
        RAISE EXCEPTION 'SQLazy per-row conservation invariant failed';
    END IF;

    IF (SELECT SUM(shortage) FROM native_allocation_result) <> 20 THEN
        RAISE EXCEPTION 'total shortage is not 20';
    END IF;

    IF (SELECT SUM(shortage) FROM sqlazy_allocation_result) <> 20 THEN
        RAISE EXCEPTION 'SQLazy total shortage is not 20';
    END IF;

    IF EXISTS (
        SELECT 1 FROM native_allocation_result WHERE order_id = 'SO999'
    ) THEN
        RAISE EXCEPTION 'cancelled order SO999 appeared in demand';
    END IF;

    IF (SELECT SUM(allocated_stock) FROM native_allocation_result)
       > (SELECT SUM(qty_on_hand - qty_reserved) FROM stock) THEN
        RAISE EXCEPTION 'opening stock was over-allocated';
    END IF;

    IF (SELECT SUM(allocated_po) FROM native_allocation_result)
       > (SELECT COALESCE(SUM(qty), 0) FROM purchase_orders WHERE status = 'CONFIRMED') THEN
        RAISE EXCEPTION 'confirmed PO supply was over-allocated';
    END IF;
END;
$$;

SELECT
    order_id,
    requested_qty,
    allocated_stock,
    allocated_po,
    shortage
FROM native_allocation_result
ORDER BY priority, required_date, order_id;

\echo 'Base verification passed.'
