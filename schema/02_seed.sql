TRUNCATE TABLE transfers, production_orders, purchase_orders, sales_orders, stock;

INSERT INTO stock (material_id, warehouse_id, qty_on_hand, qty_reserved) VALUES
    ('M100', 'W1', 120, 20),
    ('M200', 'W2', 50, 0);

INSERT INTO sales_orders (
    order_id, material_id, warehouse_id, required_date, qty, priority, status
) VALUES
    ('SO001', 'M100', 'W1', DATE '2026-09-01', 70, 1, 'OPEN'),
    ('SO002', 'M100', 'W1', DATE '2026-09-03', 80, 2, 'OPEN'),
    ('SO003', 'M100', 'W1', DATE '2026-09-05', 60, 2, 'OPEN'),
    ('SO999', 'M100', 'W1', DATE '2026-09-02', 999, 1, 'CANCELLED'),
    ('SO201', 'M200', 'W2', DATE '2026-09-02', 40, 1, 'OPEN'),
    ('SO202', 'M200', 'W2', DATE '2026-09-04', 30, 2, 'OPEN');

INSERT INTO purchase_orders (
    po_id, material_id, warehouse_id, expected_date, qty, status
) VALUES
    ('PO101', 'M100', 'W1', DATE '2026-09-02', 40, 'CONFIRMED'),
    ('PO102', 'M100', 'W1', DATE '2026-09-04', 50, 'CONFIRMED'),
    ('PO999', 'M100', 'W1', DATE '2026-09-01', 500, 'DRAFT'),
    ('PO201', 'M200', 'W2', DATE '2026-09-03', 10, 'CONFIRMED');

INSERT INTO production_orders (
    prod_id, material_id, warehouse_id, required_date, qty, status
) VALUES
    ('PROD001', 'M100', 'W1', DATE '2026-09-06', 25, 'CONFIRMED'),
    ('PROD201', 'M200', 'W2', DATE '2026-09-05', 5, 'CONFIRMED'),
    ('PROD999', 'M100', 'W1', DATE '2026-09-02', 500, 'DRAFT');

INSERT INTO transfers (
    transfer_id, material_id, from_warehouse, to_warehouse,
    expected_date, qty, status
) VALUES
    ('T201', 'M100', 'W2', 'W1', DATE '2026-09-05', 30, 'CONFIRMED'),
    ('T202', 'M200', 'W1', 'W2', DATE '2026-09-04', 5, 'CONFIRMED'),
    ('T999', 'M100', 'W2', 'W1', DATE '2026-09-01', 500, 'DRAFT');
