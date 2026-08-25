CREATE OR REPLACE FUNCTION native_allocate()
RETURNS TABLE (
    order_id text,
    material_id text,
    warehouse_id text,
    required_date date,
    priority integer,
    requested_qty bigint,
    allocated_stock bigint,
    allocated_po bigint,
    shortage bigint,
    stock_remaining bigint,
    po_remaining bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    demand_row record;
    po_row record;
    current_material text := NULL;
    current_warehouse text := NULL;
    po_balances jsonb := '{}'::jsonb;
    v_stock_remaining bigint := 0;
    v_need bigint;
    v_po_available bigint;
    v_take bigint;
BEGIN
    FOR demand_row IN
        SELECT
            so.order_id,
            so.material_id,
            so.warehouse_id,
            so.required_date,
            so.priority,
            so.qty
        FROM sales_orders AS so
        WHERE so.status = 'OPEN'
        ORDER BY
            so.material_id,
            so.warehouse_id,
            so.priority,
            so.required_date,
            so.order_id
    LOOP
        IF current_material IS DISTINCT FROM demand_row.material_id
           OR current_warehouse IS DISTINCT FROM demand_row.warehouse_id THEN
            current_material := demand_row.material_id;
            current_warehouse := demand_row.warehouse_id;

            SELECT GREATEST(s.qty_on_hand - s.qty_reserved, 0)
            INTO STRICT v_stock_remaining
            FROM stock AS s
            WHERE s.material_id = current_material
              AND s.warehouse_id = current_warehouse;

            SELECT COALESCE(jsonb_object_agg(p.po_id, p.qty), '{}'::jsonb)
            INTO po_balances
            FROM purchase_orders AS p
            WHERE p.material_id = current_material
              AND p.warehouse_id = current_warehouse
              AND p.status = 'CONFIRMED';
        END IF;

        order_id := demand_row.order_id;
        material_id := demand_row.material_id;
        warehouse_id := demand_row.warehouse_id;
        required_date := demand_row.required_date;
        priority := demand_row.priority;
        requested_qty := demand_row.qty;

        allocated_stock := LEAST(v_stock_remaining, requested_qty);
        v_stock_remaining := v_stock_remaining - allocated_stock;
        v_need := requested_qty - allocated_stock;
        allocated_po := 0;

        FOR po_row IN
            SELECT p.po_id
            FROM purchase_orders AS p
            WHERE p.material_id = current_material
              AND p.warehouse_id = current_warehouse
              AND p.status = 'CONFIRMED'
              AND p.expected_date <= demand_row.required_date
            ORDER BY p.expected_date, p.po_id
        LOOP
            EXIT WHEN allocated_po = v_need;

            v_po_available := COALESCE((po_balances ->> po_row.po_id)::bigint, 0);
            v_take := LEAST(v_po_available, v_need - allocated_po);
            allocated_po := allocated_po + v_take;
            po_balances := jsonb_set(
                po_balances,
                ARRAY[po_row.po_id],
                to_jsonb(v_po_available - v_take),
                true
            );
        END LOOP;

        shortage := requested_qty - allocated_stock - allocated_po;
        stock_remaining := v_stock_remaining;

        SELECT COALESCE(SUM(COALESCE((po_balances ->> p.po_id)::bigint, 0)), 0)
        INTO po_remaining
        FROM purchase_orders AS p
        WHERE p.material_id = current_material
          AND p.warehouse_id = current_warehouse
          AND p.status = 'CONFIRMED'
          AND p.expected_date <= demand_row.required_date;

        RETURN NEXT;
    END LOOP;
END;
$$;

CREATE OR REPLACE VIEW native_allocation_result AS
SELECT * FROM native_allocate();

