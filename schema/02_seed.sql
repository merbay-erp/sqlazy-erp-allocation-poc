TRUNCATE TABLE purchase_orders, sales_orders, stock;

INSERT INTO stock (material_id, warehouse_id, qty_on_hand, qty_reserved) VALUES
    ('M100', 'W1', 120, 20);

INSERT INTO sales_orders (
    order_id, material_id, warehouse_id, required_date, qty, priority, status
) VALUES
    ('SO001', 'M100', 'W1', DATE '2026-09-01', 70, 1, 'OPEN'),
    ('SO002', 'M100', 'W1', DATE '2026-09-03', 80, 2, 'OPEN'),
    ('SO003', 'M100', 'W1', DATE '2026-09-05', 60, 2, 'OPEN'),
    ('SO999', 'M100', 'W1', DATE '2026-09-02', 999, 1, 'CANCELLED');

INSERT INTO purchase_orders (
    po_id, material_id, warehouse_id, expected_date, qty, status
) VALUES
    ('PO101', 'M100', 'W1', DATE '2026-09-02', 40, 'CONFIRMED'),
    ('PO102', 'M100', 'W1', DATE '2026-09-04', 50, 'CONFIRMED'),
    ('PO999', 'M100', 'W1', DATE '2026-09-01', 500, 'DRAFT');

