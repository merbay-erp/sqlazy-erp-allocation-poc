BEGIN;
TRUNCATE TABLE purchase_orders, sales_orders, stock;

INSERT INTO stock VALUES ('M200', 'W1', 50, 0);
INSERT INTO sales_orders VALUES
    ('SAME_LOW', 'M200', 'W1', DATE '2026-10-01', 40, 2, 'OPEN'),
    ('SAME_HIGH', 'M200', 'W1', DATE '2026-10-01', 40, 1, 'OPEN');

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE order_id = 'SAME_HIGH'
          AND allocated_stock = 40 AND allocated_po = 0 AND shortage = 0
    ) OR NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE order_id = 'SAME_LOW'
          AND allocated_stock = 10 AND allocated_po = 0 AND shortage = 30
    ) THEN
        RAISE EXCEPTION 'same-day priority edge case failed';
    END IF;

    IF EXISTS (
        (SELECT order_id, allocated_stock, allocated_po, shortage FROM native_allocation_result
         EXCEPT
         SELECT order_id, allocated_stock, allocated_po, shortage FROM sqlazy_allocation_result)
        UNION ALL
        (SELECT order_id, allocated_stock, allocated_po, shortage FROM sqlazy_allocation_result
         EXCEPT
         SELECT order_id, allocated_stock, allocated_po, shortage FROM native_allocation_result)
    ) THEN
        RAISE EXCEPTION 'same-day priority: SQLazy compiler output and native implementation differ';
    END IF;
END;
$$;
ROLLBACK;

BEGIN;
TRUNCATE TABLE purchase_orders, sales_orders, stock;

INSERT INTO stock VALUES ('M300', 'W1', 0, 0);
INSERT INTO sales_orders VALUES
    ('LATE_DEMAND', 'M300', 'W1', DATE '2026-10-01', 10, 1, 'OPEN');
INSERT INTO purchase_orders VALUES
    ('LATE_PO', 'M300', 'W1', DATE '2026-10-02', 10, 'CONFIRMED');

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE order_id = 'LATE_DEMAND'
          AND allocated_stock = 0 AND allocated_po = 0 AND shortage = 10
    ) THEN
        RAISE EXCEPTION 'late-purchase edge case failed';
    END IF;

    IF EXISTS (
        (SELECT order_id, allocated_stock, allocated_po, shortage FROM native_allocation_result
         EXCEPT
         SELECT order_id, allocated_stock, allocated_po, shortage FROM sqlazy_allocation_result)
        UNION ALL
        (SELECT order_id, allocated_stock, allocated_po, shortage FROM sqlazy_allocation_result
         EXCEPT
         SELECT order_id, allocated_stock, allocated_po, shortage FROM native_allocation_result)
    ) THEN
        RAISE EXCEPTION 'late purchase: SQLazy compiler output and native implementation differ';
    END IF;
END;
$$;
ROLLBACK;

BEGIN;
TRUNCATE TABLE purchase_orders, sales_orders, stock;

INSERT INTO stock VALUES ('M400', 'W1', 5, 0);
INSERT INTO sales_orders VALUES
    ('EXACT_DEMAND', 'M400', 'W1', DATE '2026-10-01', 10, 1, 'OPEN');
INSERT INTO purchase_orders VALUES
    ('EXACT_PO', 'M400', 'W1', DATE '2026-10-01', 5, 'CONFIRMED');

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM native_allocation_result
        WHERE order_id = 'EXACT_DEMAND'
          AND allocated_stock = 5 AND allocated_po = 5 AND shortage = 0
          AND stock_remaining = 0 AND po_remaining = 0
    ) THEN
        RAISE EXCEPTION 'exact-balance edge case failed';
    END IF;

    IF EXISTS (
        (SELECT order_id, allocated_stock, allocated_po, shortage FROM native_allocation_result
         EXCEPT
         SELECT order_id, allocated_stock, allocated_po, shortage FROM sqlazy_allocation_result)
        UNION ALL
        (SELECT order_id, allocated_stock, allocated_po, shortage FROM sqlazy_allocation_result
         EXCEPT
         SELECT order_id, allocated_stock, allocated_po, shortage FROM native_allocation_result)
    ) THEN
        RAISE EXCEPTION 'exact balance: SQLazy compiler output and native implementation differ';
    END IF;
END;
$$;
ROLLBACK;

\echo 'All three edge cases passed.'
