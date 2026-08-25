DROP VIEW IF EXISTS sqlazy_allocation_result;
DROP VIEW IF EXISTS native_allocation_result;
DROP FUNCTION IF EXISTS native_allocate();
DROP TABLE IF EXISTS purchase_orders;
DROP TABLE IF EXISTS sales_orders;
DROP TABLE IF EXISTS stock;

CREATE TABLE stock (
    material_id text NOT NULL,
    warehouse_id text NOT NULL,
    qty_on_hand bigint NOT NULL CHECK (qty_on_hand >= 0),
    qty_reserved bigint NOT NULL CHECK (qty_reserved >= 0),
    PRIMARY KEY (material_id, warehouse_id),
    CHECK (qty_reserved <= qty_on_hand)
);

CREATE TABLE sales_orders (
    order_id text PRIMARY KEY,
    material_id text NOT NULL,
    warehouse_id text NOT NULL,
    required_date date NOT NULL,
    qty bigint NOT NULL CHECK (qty > 0),
    priority integer NOT NULL CHECK (priority > 0),
    status text NOT NULL CHECK (status IN ('OPEN', 'CANCELLED'))
);

CREATE TABLE purchase_orders (
    po_id text PRIMARY KEY,
    material_id text NOT NULL,
    warehouse_id text NOT NULL,
    expected_date date NOT NULL,
    qty bigint NOT NULL CHECK (qty > 0),
    status text NOT NULL CHECK (status IN ('CONFIRMED', 'DRAFT'))
);

CREATE INDEX sales_orders_allocation_order_idx
    ON sales_orders (material_id, warehouse_id, priority, required_date, order_id)
    WHERE status = 'OPEN';

CREATE INDEX purchase_orders_availability_idx
    ON purchase_orders (material_id, warehouse_id, expected_date, po_id)
    WHERE status = 'CONFIRMED';

