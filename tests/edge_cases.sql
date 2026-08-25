-- Every scenario is rolled back so the fixed dataset remains available.

BEGIN;
TRUNCATE TABLE transfers, production_orders, purchase_orders, sales_orders, stock;

INSERT INTO stock VALUES ('M300', 'W1', 50, 0);
INSERT INTO sales_orders VALUES
    ('SAME_LOW', 'M300', 'W1', DATE '2026-10-01', 40, 2, 'OPEN'),
    ('SAME_HIGH', 'M300', 'W1', DATE '2026-10-01', 40, 1, 'OPEN');

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE document_id = 'SAME_HIGH'
          AND allocated_from_stock = 40
          AND remaining_shortage = 0
    ) OR NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE document_id = 'SAME_LOW'
          AND allocated_from_stock = 10
          AND remaining_shortage = 30
    ) THEN
        RAISE EXCEPTION 'same-day priority edge case failed';
    END IF;

    IF EXISTS (
        (SELECT * FROM native_allocation_result EXCEPT SELECT * FROM sqlazy_allocation_result)
        UNION ALL
        (SELECT * FROM sqlazy_allocation_result EXCEPT SELECT * FROM native_allocation_result)
    ) THEN
        RAISE EXCEPTION 'same-day priority: compiler and native results differ';
    END IF;
END;
$$;
ROLLBACK;

BEGIN;
TRUNCATE TABLE transfers, production_orders, purchase_orders, sales_orders, stock;

INSERT INTO stock VALUES ('M400', 'W1', 0, 0);
INSERT INTO sales_orders VALUES
    ('LATE_DEMAND', 'M400', 'W1', DATE '2026-10-01', 10, 1, 'OPEN');
INSERT INTO purchase_orders VALUES
    ('LATE_PO', 'M400', 'W1', DATE '2026-10-02', 5, 'CONFIRMED');
INSERT INTO transfers VALUES
    ('LATE_TRANSFER', 'M400', 'W9', 'W1', DATE '2026-10-02', 5, 'CONFIRMED');

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE document_id = 'LATE_DEMAND'
          AND allocated_from_purchase_orders = 0
          AND allocated_from_transfers = 0
          AND remaining_shortage = 10
    ) THEN
        RAISE EXCEPTION 'late-supply edge case failed';
    END IF;

    IF EXISTS (
        (SELECT * FROM native_allocation_result EXCEPT SELECT * FROM sqlazy_allocation_result)
        UNION ALL
        (SELECT * FROM sqlazy_allocation_result EXCEPT SELECT * FROM native_allocation_result)
    ) THEN
        RAISE EXCEPTION 'late supply: compiler and native results differ';
    END IF;
END;
$$;
ROLLBACK;

BEGIN;
TRUNCATE TABLE transfers, production_orders, purchase_orders, sales_orders, stock;

INSERT INTO stock VALUES ('M500', 'W1', 5, 0);
INSERT INTO sales_orders VALUES
    ('EXACT_DEMAND', 'M500', 'W1', DATE '2026-10-01', 10, 1, 'OPEN');
INSERT INTO purchase_orders VALUES
    ('EXACT_PO', 'M500', 'W1', DATE '2026-10-01', 3, 'CONFIRMED');
INSERT INTO transfers VALUES
    ('EXACT_TRANSFER', 'M500', 'W9', 'W1', DATE '2026-10-01', 2, 'CONFIRMED');

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE document_id = 'EXACT_DEMAND'
          AND allocated_from_stock = 5
          AND allocated_from_purchase_orders = 3
          AND allocated_from_transfers = 2
          AND remaining_shortage = 0
          AND projected_stock_after_allocation = 0
    ) THEN
        RAISE EXCEPTION 'exact-balance edge case failed';
    END IF;

    IF EXISTS (
        (SELECT * FROM native_allocation_result EXCEPT SELECT * FROM sqlazy_allocation_result)
        UNION ALL
        (SELECT * FROM sqlazy_allocation_result EXCEPT SELECT * FROM native_allocation_result)
    ) THEN
        RAISE EXCEPTION 'exact balance: compiler and native results differ';
    END IF;
END;
$$;
ROLLBACK;

BEGIN;
TRUNCATE TABLE transfers, production_orders, purchase_orders, sales_orders, stock;

INSERT INTO stock VALUES
    ('M600', 'W1', 10, 0),
    ('M600', 'W2', 0, 0);
INSERT INTO sales_orders VALUES
    ('W1_SALE', 'M600', 'W1', DATE '2026-10-01', 10, 1, 'OPEN'),
    ('W2_SALE', 'M600', 'W2', DATE '2026-10-01', 10, 1, 'OPEN');
INSERT INTO production_orders VALUES
    ('W1_PROD', 'M600', 'W1', DATE '2026-10-01', 5, 'CONFIRMED');
INSERT INTO transfers VALUES
    ('TO_W2', 'M600', 'W9', 'W2', DATE '2026-10-01', 10, 'CONFIRMED');

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE document_id = 'W1_SALE'
          AND allocated_from_stock = 10
          AND remaining_shortage = 0
    ) OR NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE document_id = 'W1_PROD'
          AND allocated_from_transfers = 0
          AND remaining_shortage = 5
    ) OR NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE document_id = 'W2_SALE'
          AND allocated_from_stock = 0
          AND allocated_from_transfers = 10
          AND remaining_shortage = 0
    ) THEN
        RAISE EXCEPTION 'production priority, partition, or transfer destination case failed';
    END IF;

    IF EXISTS (
        (SELECT * FROM native_allocation_result EXCEPT SELECT * FROM sqlazy_allocation_result)
        UNION ALL
        (SELECT * FROM sqlazy_allocation_result EXCEPT SELECT * FROM native_allocation_result)
    ) THEN
        RAISE EXCEPTION 'multi-stream production/transfer: compiler and native results differ';
    END IF;
END;
$$;
ROLLBACK;

BEGIN;
TRUNCATE TABLE transfers, production_orders, purchase_orders, sales_orders, stock;

INSERT INTO stock VALUES ('M900', 'W1', 0, 0);
INSERT INTO sales_orders VALUES
    ('LATE_HIGH', 'M900', 'W1', DATE '2026-10-10', 10, 1, 'OPEN'),
    ('EARLY_LOW', 'M900', 'W1', DATE '2026-10-01', 5, 2, 'OPEN');
INSERT INTO purchase_orders VALUES
    ('DATE_REVERSAL_PO', 'M900', 'W1', DATE '2026-10-05', 10, 'CONFIRMED');

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE document_id = 'LATE_HIGH'
          AND allocated_from_purchase_orders = 10
          AND remaining_shortage = 0
    ) OR NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE document_id = 'EARLY_LOW'
          AND allocated_from_purchase_orders = 0
          AND remaining_shortage = 5
    ) THEN
        RAISE EXCEPTION 'priority/date reversal reference case failed';
    END IF;

    IF EXISTS (
        SELECT 1 FROM sqlazy_allocation_result
        WHERE allocated_from_purchase_orders < 0
           OR allocated_from_transfers < 0
           OR remaining_shortage < 0
    ) THEN
        RAISE EXCEPTION 'priority/date reversal produced a negative allocation';
    END IF;

    IF EXISTS (
        (SELECT * FROM native_allocation_result EXCEPT SELECT * FROM sqlazy_allocation_result)
        UNION ALL
        (SELECT * FROM sqlazy_allocation_result EXCEPT SELECT * FROM native_allocation_result)
    ) THEN
        RAISE EXCEPTION 'priority/date reversal: compiler and native results differ';
    END IF;
END;
$$;
ROLLBACK;

BEGIN;
TRUNCATE TABLE transfers, production_orders, purchase_orders, sales_orders, stock;

INSERT INTO sales_orders VALUES
    ('NO_STOCK_ROW', 'M950', 'W1', DATE '2026-10-01', 10, 1, 'OPEN');
INSERT INTO purchase_orders VALUES
    ('NO_STOCK_PO', 'M950', 'W1', DATE '2026-10-01', 5, 'CONFIRMED');

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE document_id = 'NO_STOCK_ROW'
          AND allocated_from_stock = 0
          AND allocated_from_purchase_orders = 5
          AND remaining_shortage = 5
    ) THEN
        RAISE EXCEPTION 'missing stock row must behave as zero opening stock';
    END IF;

    IF EXISTS (
        (SELECT * FROM native_allocation_result EXCEPT SELECT * FROM sqlazy_allocation_result)
        UNION ALL
        (SELECT * FROM sqlazy_allocation_result EXCEPT SELECT * FROM native_allocation_result)
    ) THEN
        RAISE EXCEPTION 'missing stock row: compiler and native results differ';
    END IF;
END;
$$;
ROLLBACK;

\echo 'Six edge scenarios passed: priority, late supply, exact balance, multi-stream isolation, priority/date reversal, and missing stock row.'
