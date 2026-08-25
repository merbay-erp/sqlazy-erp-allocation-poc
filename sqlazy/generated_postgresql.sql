-- SQLazy web compiler output captured on 2026-08-25 with target POSTGRES.
-- Only this CREATE VIEW wrapper was added for the repeatable test harness;
-- the compiler-produced WITH/SELECT statement below is otherwise unchanged.
CREATE OR REPLACE VIEW sqlazy_allocation_result AS
WITH stock_valid AS (
  SELECT
    material_id,
    warehouse_id,
    qty_on_hand,
    qty_reserved,
    qty_on_hand - qty_reserved AS usable_stock
  FROM
    stock
),
po_confirmed AS (
  SELECT
    po_id,
    material_id,
    warehouse_id,
    expected_date,
    qty,
    status
  FROM
    purchase_orders
  WHERE
    status = 'CONFIRMED'
),
demand_po_rows AS (
  SELECT
    sales_orders.order_id,
    sales_orders.material_id,
    sales_orders.warehouse_id,
    sales_orders.required_date,
    sales_orders.qty,
    sales_orders.priority,
    sales_orders.status,
    stock_valid.usable_stock,
    po_confirmed.expected_date,
    po_confirmed.qty AS po_qty
  FROM
    sales_orders
    INNER JOIN stock_valid ON sales_orders.material_id = stock_valid.material_id
    AND sales_orders.warehouse_id = stock_valid.warehouse_id
    LEFT JOIN po_confirmed ON sales_orders.material_id = po_confirmed.material_id
    AND sales_orders.warehouse_id = po_confirmed.warehouse_id
  WHERE
    sales_orders.status = 'OPEN'
),
demand_resorted AS (
  SELECT
    order_id,
    MAX(col_2) AS material_id,
    MAX(col_4) AS warehouse_id,
    MAX(col_5) AS required_date,
    MAX(col_6) AS requested_qty,
    MAX(col_7) AS priority,
    MAX(col_8) AS usable_stock,
    SUM(
      CASE
        WHEN expected_date <= required_date THEN po_qty
        ELSE NULL
      END
    ) AS cumulative_po
  FROM
    (
      SELECT
        order_id,
        material_id,
        warehouse_id,
        required_date,
        qty,
        priority,
        status,
        usable_stock,
        expected_date,
        po_qty,
        FIRST_VALUE(material_id) OVER (
          PARTITION BY order_id
          ORDER BY
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            order_id ASC NULLS FIRST
        ) AS col_2,
        FIRST_VALUE(warehouse_id) OVER (
          PARTITION BY order_id
          ORDER BY
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            order_id ASC NULLS FIRST
        ) AS col_4,
        FIRST_VALUE(required_date) OVER (
          PARTITION BY order_id
          ORDER BY
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            order_id ASC NULLS FIRST
        ) AS col_5,
        FIRST_VALUE(qty) OVER (
          PARTITION BY order_id
          ORDER BY
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            order_id ASC NULLS FIRST
        ) AS col_6,
        FIRST_VALUE(priority) OVER (
          PARTITION BY order_id
          ORDER BY
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            order_id ASC NULLS FIRST
        ) AS col_7,
        FIRST_VALUE(usable_stock) OVER (
          PARTITION BY order_id
          ORDER BY
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            order_id ASC NULLS FIRST
        ) AS col_8
      FROM
        demand_po_rows
    ) t_9
  GROUP BY
    order_id
),
demand_cum AS (
  SELECT
    order_id,
    material_id,
    warehouse_id,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    cumulative_po,
    CASE
      WHEN cumulative_po IS NULL THEN 0
      ELSE cumulative_po
    END - CASE
      WHEN LAG(cumulative_po, 1) OVER (
        ORDER BY
          priority ASC NULLS FIRST,
          required_date ASC NULLS FIRST,
          order_id ASC NULLS FIRST
      ) IS NULL THEN 0
      ELSE LAG(cumulative_po, 1) OVER (
        ORDER BY
          priority ASC NULLS FIRST,
          required_date ASC NULLS FIRST,
          order_id ASC NULLS FIRST
      )
    END AS new_po,
    SUM(requested_qty) OVER (
      ORDER BY
        priority ASC NULLS FIRST,
        required_date ASC NULLS FIRST,
        order_id ASC NULLS FIRST ROWS UNBOUNDED PRECEDING
    ) AS cumulative_demand
  FROM
    demand_resorted
),
stock_alloc AS (
  SELECT
    order_id,
    material_id,
    warehouse_id,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    cumulative_po,
    new_po,
    cumulative_demand,
    CASE
      WHEN usable_stock >= cumulative_demand THEN usable_stock - cumulative_demand
      ELSE 0
    END AS stock_remaining,
    CASE
      WHEN usable_stock >= cumulative_demand THEN requested_qty
      ELSE CASE
        WHEN usable_stock > cumulative_demand - requested_qty THEN usable_stock - (cumulative_demand - requested_qty)
        ELSE 0
      END
    END AS allocated_stock
  FROM
    demand_cum
),
po_need AS (
  SELECT
    order_id,
    material_id,
    warehouse_id,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    cumulative_po,
    new_po,
    cumulative_demand,
    stock_remaining,
    allocated_stock,
    requested_qty - allocated_stock AS demand_after_stock
  FROM
    stock_alloc
),
po_net AS (
  SELECT
    order_id,
    material_id,
    warehouse_id,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    cumulative_po,
    new_po,
    cumulative_demand,
    stock_remaining,
    allocated_stock,
    demand_after_stock,
    SUM(new_po - demand_after_stock) OVER (
      ORDER BY
        priority ASC NULLS FIRST,
        required_date ASC NULLS FIRST,
        order_id ASC NULLS FIRST ROWS UNBOUNDED PRECEDING
    ) AS po_net_cumulative
  FROM
    po_need
),
po_min AS (
  SELECT
    order_id,
    material_id,
    warehouse_id,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    cumulative_po,
    new_po,
    cumulative_demand,
    stock_remaining,
    allocated_stock,
    demand_after_stock,
    po_net_cumulative,
    MIN(po_net_cumulative) OVER (
      ORDER BY
        priority ASC NULLS FIRST,
        required_date ASC NULLS FIRST,
        order_id ASC NULLS FIRST ROWS BETWEEN 1000000 PRECEDING
        AND CURRENT ROW
    ) AS po_min_cumulative
  FROM
    po_net
),
po_regulator AS (
  SELECT
    order_id,
    material_id,
    warehouse_id,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    cumulative_po,
    new_po,
    cumulative_demand,
    stock_remaining,
    allocated_stock,
    demand_after_stock,
    po_net_cumulative,
    po_min_cumulative,
    CASE
      WHEN po_min_cumulative < 0 THEN 0 - po_min_cumulative
      ELSE 0
    END AS po_shortage_cumulative
  FROM
    po_min
),
shortage_delta AS (
  SELECT
    order_id,
    material_id,
    warehouse_id,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    cumulative_po,
    new_po,
    cumulative_demand,
    stock_remaining,
    allocated_stock,
    demand_after_stock,
    po_net_cumulative,
    po_min_cumulative,
    po_shortage_cumulative,
    po_shortage_cumulative - CASE
      WHEN LAG(po_shortage_cumulative, 1) OVER (
        ORDER BY
          priority ASC NULLS FIRST,
          required_date ASC NULLS FIRST,
          order_id ASC NULLS FIRST
      ) IS NULL THEN 0
      ELSE LAG(po_shortage_cumulative, 1) OVER (
        ORDER BY
          priority ASC NULLS FIRST,
          required_date ASC NULLS FIRST,
          order_id ASC NULLS FIRST
      )
    END AS shortage
  FROM
    po_regulator
),
po_balance AS (
  SELECT
    order_id,
    material_id,
    warehouse_id,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    cumulative_po,
    new_po,
    cumulative_demand,
    stock_remaining,
    allocated_stock,
    demand_after_stock,
    po_net_cumulative,
    po_min_cumulative,
    po_shortage_cumulative,
    shortage,
    demand_after_stock - shortage AS allocated_po,
    po_net_cumulative + po_shortage_cumulative AS po_remaining
  FROM
    shortage_delta
)
SELECT
  order_id,
  material_id,
  warehouse_id,
  required_date,
  priority,
  requested_qty,
  allocated_stock,
  allocated_po,
  shortage,
  stock_remaining,
  po_remaining
FROM
  po_balance
ORDER BY
  priority ASC NULLS FIRST,
  required_date ASC NULLS FIRST,
  order_id ASC NULLS FIRST;
