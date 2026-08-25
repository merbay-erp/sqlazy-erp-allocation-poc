CREATE TEMP TABLE expected_result (
    material_id text NOT NULL,
    warehouse_id text NOT NULL,
    demand_type text NOT NULL,
    document_id text PRIMARY KEY,
    required_date date NOT NULL,
    requested_qty bigint NOT NULL,
    allocated_from_stock bigint NOT NULL,
    allocated_from_purchase_orders bigint NOT NULL,
    allocated_from_transfers bigint NOT NULL,
    remaining_shortage bigint NOT NULL,
    projected_stock_after_allocation bigint NOT NULL
);

\copy expected_result FROM 'expected/expected_result.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE sqlazy_web_result (LIKE expected_result INCLUDING ALL);

\copy sqlazy_web_result FROM 'sqlazy/execution_result.csv' WITH (FORMAT csv, HEADER true)

DO $$
BEGIN
    IF EXISTS (
        (SELECT * FROM sqlazy_web_result EXCEPT SELECT * FROM expected_result)
        UNION ALL
        (SELECT * FROM expected_result EXCEPT SELECT * FROM sqlazy_web_result)
    ) THEN
        RAISE EXCEPTION 'captured SQLazy web result does not match expected_result.csv';
    END IF;

    IF EXISTS (
        (SELECT * FROM native_allocation_result EXCEPT SELECT * FROM expected_result)
        UNION ALL
        (SELECT * FROM expected_result EXCEPT SELECT * FROM native_allocation_result)
    ) THEN
        RAISE EXCEPTION 'native allocation does not match expected_result.csv';
    END IF;

    IF EXISTS (
        (SELECT * FROM sqlazy_allocation_result EXCEPT SELECT * FROM expected_result)
        UNION ALL
        (SELECT * FROM expected_result EXCEPT SELECT * FROM sqlazy_allocation_result)
    ) THEN
        RAISE EXCEPTION 'SQLazy compiler output does not match expected_result.csv';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            SELECT * FROM native_allocation_result
            UNION ALL
            SELECT * FROM sqlazy_allocation_result
        ) AS result
        WHERE requested_qty <>
            allocated_from_stock
            + allocated_from_purchase_orders
            + allocated_from_transfers
            + remaining_shortage
           OR LEAST(
                allocated_from_stock,
                allocated_from_purchase_orders,
                allocated_from_transfers,
                remaining_shortage,
                projected_stock_after_allocation
              ) < 0
    ) THEN
        RAISE EXCEPTION 'allocation conservation or non-negative invariant failed';
    END IF;

    IF (SELECT COUNT(*) FROM native_allocation_result) <> 7
       OR (SELECT COUNT(*) FROM sqlazy_allocation_result) <> 7 THEN
        RAISE EXCEPTION 'expected exactly seven valid demand rows';
    END IF;

    IF (SELECT SUM(remaining_shortage) FROM native_allocation_result) <> 25
       OR (SELECT SUM(remaining_shortage) FROM sqlazy_allocation_result) <> 25 THEN
        RAISE EXCEPTION 'total shortage is not 25';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM native_allocation_result
        WHERE document_id IN ('SO999', 'PROD999')
    ) OR EXISTS (
        SELECT 1
        FROM sqlazy_allocation_result
        WHERE document_id IN ('SO999', 'PROD999')
    ) THEN
        RAISE EXCEPTION 'cancelled or draft demand appeared in output';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            SELECT
                material_id,
                warehouse_id,
                SUM(allocated_from_stock) AS allocated
            FROM sqlazy_allocation_result
            GROUP BY material_id, warehouse_id
        ) AS a
        JOIN stock AS s USING (material_id, warehouse_id)
        WHERE a.allocated > s.qty_on_hand - s.qty_reserved
    ) THEN
        RAISE EXCEPTION 'opening stock was over-allocated';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            SELECT
                material_id,
                warehouse_id,
                SUM(allocated_from_purchase_orders) AS allocated
            FROM sqlazy_allocation_result
            GROUP BY material_id, warehouse_id
        ) AS a
        LEFT JOIN (
            SELECT material_id, warehouse_id, SUM(qty) AS available
            FROM purchase_orders
            WHERE status = 'CONFIRMED'
            GROUP BY material_id, warehouse_id
        ) AS p USING (material_id, warehouse_id)
        WHERE a.allocated > COALESCE(p.available, 0)
    ) THEN
        RAISE EXCEPTION 'confirmed purchase supply was over-allocated';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            SELECT
                material_id,
                warehouse_id,
                SUM(allocated_from_transfers) AS allocated
            FROM sqlazy_allocation_result
            GROUP BY material_id, warehouse_id
        ) AS a
        LEFT JOIN (
            SELECT
                material_id,
                to_warehouse AS warehouse_id,
                SUM(qty) AS available
            FROM transfers
            WHERE status = 'CONFIRMED'
            GROUP BY material_id, to_warehouse
        ) AS t USING (material_id, warehouse_id)
        WHERE a.allocated > COALESCE(t.available, 0)
    ) THEN
        RAISE EXCEPTION 'confirmed destination transfer supply was over-allocated';
    END IF;
END;
$$;

TABLE sqlazy_allocation_result;

\echo 'Base verification passed: web runtime = expected = compiler SQL = native reference.'
