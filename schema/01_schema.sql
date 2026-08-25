DROP VIEW IF EXISTS sqlazy_allocation_result;
DROP VIEW IF EXISTS native_allocation_result;
DROP VIEW IF EXISTS supply_events_sqlazy;
DROP FUNCTION IF EXISTS native_allocate();
DROP TABLE IF EXISTS transfers;
DROP TABLE IF EXISTS production_orders;
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

CREATE TABLE production_orders (
    prod_id text PRIMARY KEY,
    material_id text NOT NULL,
    warehouse_id text NOT NULL,
    required_date date NOT NULL,
    qty bigint NOT NULL CHECK (qty > 0),
    status text NOT NULL CHECK (status IN ('CONFIRMED', 'DRAFT', 'CANCELLED'))
);

CREATE TABLE transfers (
    transfer_id text PRIMARY KEY,
    material_id text NOT NULL,
    from_warehouse text NOT NULL,
    to_warehouse text NOT NULL,
    expected_date date NOT NULL,
    qty bigint NOT NULL CHECK (qty > 0),
    status text NOT NULL CHECK (status IN ('CONFIRMED', 'DRAFT', 'CANCELLED')),
    CHECK (from_warehouse <> to_warehouse)
);

-- SQLazy's PostgreSQL compiler cannot compile a second join after an aggregate.
-- Keep the ERP source tables unchanged and expose both inbound supply types as
-- one event stream so the workflow needs only one supply join.
CREATE VIEW supply_events_sqlazy AS
SELECT
    po_id AS supply_id,
    material_id,
    warehouse_id,
    'PURCHASE_ORDER'::text AS supply_type,
    expected_date AS available_date,
    qty,
    status
FROM purchase_orders
UNION ALL
SELECT
    transfer_id AS supply_id,
    material_id,
    to_warehouse AS warehouse_id,
    'TRANSFER'::text AS supply_type,
    expected_date AS available_date,
    qty,
    status
FROM transfers;

CREATE INDEX sales_orders_allocation_order_idx
    ON sales_orders (material_id, warehouse_id, priority, required_date, order_id)
    WHERE status = 'OPEN';

CREATE INDEX purchase_orders_availability_idx
    ON purchase_orders (material_id, warehouse_id, expected_date, po_id)
    WHERE status = 'CONFIRMED';

CREATE INDEX production_orders_allocation_order_idx
    ON production_orders (material_id, warehouse_id, required_date, prod_id)
    WHERE status = 'CONFIRMED';

CREATE INDEX transfers_destination_availability_idx
    ON transfers (material_id, to_warehouse, expected_date, transfer_id)
    WHERE status = 'CONFIRMED';
