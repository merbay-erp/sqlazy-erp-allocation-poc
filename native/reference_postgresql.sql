CREATE OR REPLACE FUNCTION native_allocate()
RETURNS TABLE (
    material_id text,
    warehouse_id text,
    demand_type text,
    document_id text,
    required_date date,
    priority integer,
    requested_qty bigint,
    allocated_from_stock bigint,
    allocated_from_purchase_orders bigint,
    allocated_from_transfers bigint,
    remaining_shortage bigint,
    projected_stock_after_allocation bigint,
    stock_remaining bigint,
    po_remaining bigint,
    transfer_remaining bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    demand_row record;
    supply_row record;
    current_material text := NULL;
    current_warehouse text := NULL;
    po_balances jsonb := '{}'::jsonb;
    transfer_balances jsonb := '{}'::jsonb;
    v_stock_remaining bigint := 0;
    v_need bigint;
    v_available bigint;
    v_take bigint;
BEGIN
    FOR demand_row IN
        SELECT *
        FROM (
            SELECT
                so.material_id,
                so.warehouse_id,
                'SALES'::text AS demand_type,
                so.order_id AS document_id,
                so.required_date,
                so.priority,
                so.qty AS requested_qty
            FROM sales_orders AS so
            WHERE so.status = 'OPEN'

            UNION ALL

            SELECT
                prod.material_id,
                prod.warehouse_id,
                'PRODUCTION'::text AS demand_type,
                prod.prod_id AS document_id,
                prod.required_date,
                3 AS priority,
                prod.qty AS requested_qty
            FROM production_orders AS prod
            WHERE prod.status = 'CONFIRMED'
        ) AS demand
        ORDER BY
            demand.material_id,
            demand.warehouse_id,
            demand.priority,
            demand.required_date,
            demand.document_id
    LOOP
        IF current_material IS DISTINCT FROM demand_row.material_id
           OR current_warehouse IS DISTINCT FROM demand_row.warehouse_id THEN
            current_material := demand_row.material_id;
            current_warehouse := demand_row.warehouse_id;

            SELECT COALESCE(
                MAX(GREATEST(s.qty_on_hand - s.qty_reserved, 0)),
                0
            )
            INTO v_stock_remaining
            FROM stock AS s
            WHERE s.material_id = current_material
              AND s.warehouse_id = current_warehouse;

            SELECT COALESCE(jsonb_object_agg(po.po_id, po.qty), '{}'::jsonb)
            INTO po_balances
            FROM purchase_orders AS po
            WHERE po.material_id = current_material
              AND po.warehouse_id = current_warehouse
              AND po.status = 'CONFIRMED';

            SELECT COALESCE(jsonb_object_agg(t.transfer_id, t.qty), '{}'::jsonb)
            INTO transfer_balances
            FROM transfers AS t
            WHERE t.material_id = current_material
              AND t.to_warehouse = current_warehouse
              AND t.status = 'CONFIRMED';
        END IF;

        material_id := demand_row.material_id;
        warehouse_id := demand_row.warehouse_id;
        demand_type := demand_row.demand_type;
        document_id := demand_row.document_id;
        required_date := demand_row.required_date;
        priority := demand_row.priority;
        requested_qty := demand_row.requested_qty;

        allocated_from_stock := LEAST(v_stock_remaining, requested_qty);
        v_stock_remaining := v_stock_remaining - allocated_from_stock;
        v_need := requested_qty - allocated_from_stock;
        allocated_from_purchase_orders := 0;

        FOR supply_row IN
            SELECT po.po_id AS supply_id
            FROM purchase_orders AS po
            WHERE po.material_id = current_material
              AND po.warehouse_id = current_warehouse
              AND po.status = 'CONFIRMED'
              AND po.expected_date <= demand_row.required_date
            ORDER BY po.expected_date, po.po_id
        LOOP
            EXIT WHEN allocated_from_purchase_orders = v_need;
            v_available := COALESCE(
                (po_balances ->> supply_row.supply_id)::bigint,
                0
            );
            v_take := LEAST(
                v_available,
                v_need - allocated_from_purchase_orders
            );
            allocated_from_purchase_orders :=
                allocated_from_purchase_orders + v_take;
            po_balances := jsonb_set(
                po_balances,
                ARRAY[supply_row.supply_id],
                to_jsonb(v_available - v_take),
                true
            );
        END LOOP;

        v_need := v_need - allocated_from_purchase_orders;
        allocated_from_transfers := 0;

        FOR supply_row IN
            SELECT t.transfer_id AS supply_id
            FROM transfers AS t
            WHERE t.material_id = current_material
              AND t.to_warehouse = current_warehouse
              AND t.status = 'CONFIRMED'
              AND t.expected_date <= demand_row.required_date
            ORDER BY t.expected_date, t.transfer_id
        LOOP
            EXIT WHEN allocated_from_transfers = v_need;
            v_available := COALESCE(
                (transfer_balances ->> supply_row.supply_id)::bigint,
                0
            );
            v_take := LEAST(
                v_available,
                v_need - allocated_from_transfers
            );
            allocated_from_transfers := allocated_from_transfers + v_take;
            transfer_balances := jsonb_set(
                transfer_balances,
                ARRAY[supply_row.supply_id],
                to_jsonb(v_available - v_take),
                true
            );
        END LOOP;

        remaining_shortage := v_need - allocated_from_transfers;
        stock_remaining := v_stock_remaining;

        SELECT COALESCE(
            SUM(COALESCE((po_balances ->> po.po_id)::bigint, 0)),
            0
        )
        INTO po_remaining
        FROM purchase_orders AS po
        WHERE po.material_id = current_material
          AND po.warehouse_id = current_warehouse
          AND po.status = 'CONFIRMED'
          AND po.expected_date <= demand_row.required_date;

        SELECT COALESCE(
            SUM(COALESCE(
                (transfer_balances ->> t.transfer_id)::bigint,
                0
            )),
            0
        )
        INTO transfer_remaining
        FROM transfers AS t
        WHERE t.material_id = current_material
          AND t.to_warehouse = current_warehouse
          AND t.status = 'CONFIRMED'
          AND t.expected_date <= demand_row.required_date;

        projected_stock_after_allocation :=
            stock_remaining + po_remaining + transfer_remaining;

        RETURN NEXT;
    END LOOP;
END;
$$;

CREATE OR REPLACE VIEW native_allocation_result AS
SELECT
    material_id,
    warehouse_id,
    demand_type,
    document_id,
    required_date,
    requested_qty,
    allocated_from_stock,
    allocated_from_purchase_orders,
    allocated_from_transfers,
    remaining_shortage,
    projected_stock_after_allocation
FROM native_allocate();
