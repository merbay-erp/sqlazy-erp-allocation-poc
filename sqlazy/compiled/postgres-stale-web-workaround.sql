-- Current SQLazy POSTGRES compiler output from sqlazy/allocation.nspl.
-- Captured from https://www.sqlazy.com/ on 2026-08-27.
CREATE OR REPLACE VIEW sqlazy_allocation_result AS
WITH sales_demand AS (
  SELECT
    concat_ws('', material_id, '|', warehouse_id) AS stream_key,
    material_id,
    warehouse_id,
    'SALES' AS demand_type,
    order_id AS document_id,
    required_date,
    qty AS requested_qty,
    priority
  FROM
    sales_orders
  WHERE
    status = 'OPEN'
    AND qty > 0
),
production_demand AS (
  SELECT
    concat_ws('', material_id, '|', warehouse_id) AS stream_key,
    material_id,
    warehouse_id,
    'PRODUCTION' AS demand_type,
    prod_id AS document_id,
    required_date,
    qty AS requested_qty,
    3 AS priority
  FROM
    production_orders
  WHERE
    status = 'CONFIRMED'
    AND qty > 0
),
demand_all AS (
  SELECT
    *
  FROM
    sales_demand
  UNION ALL
  SELECT
    *
  FROM
    production_demand
),
stock_valid AS (
  SELECT
    material_id,
    warehouse_id,
    qty_on_hand,
    qty_reserved,
    qty_on_hand - qty_reserved AS usable_stock
  FROM
    stock
),
supply_events_ready AS (
  SELECT
    supply_id,
    material_id,
    warehouse_id,
    supply_type,
    available_date,
    qty,
    status
  FROM
    supply_events_sqlazy
  WHERE
    status = 'CONFIRMED'
    AND qty > 0
),
demand_supply_rows AS (
  SELECT
    demand_all.stream_key,
    demand_all.material_id,
    demand_all.warehouse_id,
    demand_all.demand_type,
    demand_all.document_id,
    demand_all.required_date,
    demand_all.requested_qty,
    demand_all.priority,
    stock_valid.usable_stock,
    supply_events_ready.supply_type,
    supply_events_ready.available_date,
    supply_events_ready.qty AS supply_qty
  FROM
    demand_all
    LEFT JOIN stock_valid ON demand_all.material_id = stock_valid.material_id
    AND demand_all.warehouse_id = stock_valid.warehouse_id
    LEFT JOIN supply_events_ready ON demand_all.material_id = supply_events_ready.material_id
    AND demand_all.warehouse_id = supply_events_ready.warehouse_id
),
demand_resorted AS (
  SELECT
    document_id,
    MAX(col_2) AS stream_key,
    MAX(col_4) AS material_id,
    MAX(col_5) AS warehouse_id,
    MAX(col_6) AS demand_type,
    MAX(col_7) AS required_date,
    MAX(col_8) AS requested_qty,
    MAX(col_9) AS priority,
    MAX(col_10) AS usable_stock,
    SUM(supply_qty) AS compatibility_filter_seed,
    SUM(
      CASE
        WHEN (
          supply_type = 'PURCHASE_ORDER'
          AND available_date <= required_date
        ) THEN supply_qty
        ELSE NULL
      END
    ) AS cumulative_po,
    SUM(
      CASE
        WHEN (
          supply_type = 'TRANSFER'
          AND available_date <= required_date
        ) THEN supply_qty
        ELSE NULL
      END
    ) AS cumulative_transfer
  FROM
    (
      SELECT
        stream_key,
        material_id,
        warehouse_id,
        demand_type,
        document_id,
        required_date,
        requested_qty,
        priority,
        usable_stock,
        supply_type,
        available_date,
        supply_qty,
        FIRST_VALUE(stream_key) OVER (
          PARTITION BY document_id
          ORDER BY
            stream_key ASC NULLS FIRST,
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            document_id ASC NULLS FIRST
        ) AS col_2,
        FIRST_VALUE(material_id) OVER (
          PARTITION BY document_id
          ORDER BY
            stream_key ASC NULLS FIRST,
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            document_id ASC NULLS FIRST
        ) AS col_4,
        FIRST_VALUE(warehouse_id) OVER (
          PARTITION BY document_id
          ORDER BY
            stream_key ASC NULLS FIRST,
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            document_id ASC NULLS FIRST
        ) AS col_5,
        FIRST_VALUE(demand_type) OVER (
          PARTITION BY document_id
          ORDER BY
            stream_key ASC NULLS FIRST,
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            document_id ASC NULLS FIRST
        ) AS col_6,
        FIRST_VALUE(required_date) OVER (
          PARTITION BY document_id
          ORDER BY
            stream_key ASC NULLS FIRST,
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            document_id ASC NULLS FIRST
        ) AS col_7,
        FIRST_VALUE(requested_qty) OVER (
          PARTITION BY document_id
          ORDER BY
            stream_key ASC NULLS FIRST,
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            document_id ASC NULLS FIRST
        ) AS col_8,
        FIRST_VALUE(priority) OVER (
          PARTITION BY document_id
          ORDER BY
            stream_key ASC NULLS FIRST,
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            document_id ASC NULLS FIRST
        ) AS col_9,
        FIRST_VALUE(usable_stock) OVER (
          PARTITION BY document_id
          ORDER BY
            stream_key ASC NULLS FIRST,
            priority ASC NULLS FIRST,
            required_date ASC NULLS FIRST,
            document_id ASC NULLS FIRST
        ) AS col_10
      FROM
        demand_supply_rows
    ) t_11
  GROUP BY
    document_id
),
supply_frontier AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    MAX(cumulative_po) OVER (
      PARTITION BY stream_key
      ORDER BY
        stream_key ASC NULLS FIRST,
        priority ASC NULLS FIRST,
        required_date ASC NULLS FIRST,
        document_id ASC NULLS FIRST ROWS BETWEEN 1000000 PRECEDING
        AND CURRENT ROW
    ) AS po_frontier,
    MAX(cumulative_transfer) OVER (
      PARTITION BY stream_key
      ORDER BY
        stream_key ASC NULLS FIRST,
        priority ASC NULLS FIRST,
        required_date ASC NULLS FIRST,
        document_id ASC NULLS FIRST ROWS BETWEEN 1000000 PRECEDING
        AND CURRENT ROW
    ) AS transfer_frontier
  FROM
    demand_resorted
),
demand_cum AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    po_frontier,
    transfer_frontier,
    CASE
      WHEN po_frontier IS NULL THEN 0
      ELSE po_frontier
    END - CASE
      WHEN LAG(po_frontier, 1) OVER (
        PARTITION BY stream_key
        ORDER BY
          stream_key ASC NULLS FIRST,
          priority ASC NULLS FIRST,
          required_date ASC NULLS FIRST,
          document_id ASC NULLS FIRST
      ) IS NULL THEN 0
      ELSE LAG(po_frontier, 1) OVER (
        PARTITION BY stream_key
        ORDER BY
          stream_key ASC NULLS FIRST,
          priority ASC NULLS FIRST,
          required_date ASC NULLS FIRST,
          document_id ASC NULLS FIRST
      )
    END AS new_po,
    CASE
      WHEN transfer_frontier IS NULL THEN 0
      ELSE transfer_frontier
    END - CASE
      WHEN LAG(transfer_frontier, 1) OVER (
        PARTITION BY stream_key
        ORDER BY
          stream_key ASC NULLS FIRST,
          priority ASC NULLS FIRST,
          required_date ASC NULLS FIRST,
          document_id ASC NULLS FIRST
      ) IS NULL THEN 0
      ELSE LAG(transfer_frontier, 1) OVER (
        PARTITION BY stream_key
        ORDER BY
          stream_key ASC NULLS FIRST,
          priority ASC NULLS FIRST,
          required_date ASC NULLS FIRST,
          document_id ASC NULLS FIRST
      )
    END AS new_transfer,
    SUM(requested_qty) OVER (
      PARTITION BY stream_key
      ORDER BY
        stream_key ASC NULLS FIRST,
        priority ASC NULLS FIRST,
        required_date ASC NULLS FIRST,
        document_id ASC NULLS FIRST ROWS UNBOUNDED PRECEDING
    ) AS cumulative_demand
  FROM
    supply_frontier
),
stock_alloc AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    po_frontier,
    transfer_frontier,
    new_po,
    new_transfer,
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
    END AS allocated_from_stock
  FROM
    demand_cum
),
po_need AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    po_frontier,
    transfer_frontier,
    new_po,
    new_transfer,
    cumulative_demand,
    stock_remaining,
    allocated_from_stock,
    requested_qty - allocated_from_stock AS demand_after_stock
  FROM
    stock_alloc
),
po_net AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    po_frontier,
    transfer_frontier,
    new_po,
    new_transfer,
    cumulative_demand,
    stock_remaining,
    allocated_from_stock,
    demand_after_stock,
    SUM(new_po - demand_after_stock) OVER (
      PARTITION BY stream_key
      ORDER BY
        stream_key ASC NULLS FIRST,
        priority ASC NULLS FIRST,
        required_date ASC NULLS FIRST,
        document_id ASC NULLS FIRST ROWS UNBOUNDED PRECEDING
    ) AS po_net_cumulative
  FROM
    po_need
),
po_min AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    po_frontier,
    transfer_frontier,
    new_po,
    new_transfer,
    cumulative_demand,
    stock_remaining,
    allocated_from_stock,
    demand_after_stock,
    po_net_cumulative,
    MIN(po_net_cumulative) OVER (
      PARTITION BY stream_key
      ORDER BY
        stream_key ASC NULLS FIRST,
        priority ASC NULLS FIRST,
        required_date ASC NULLS FIRST,
        document_id ASC NULLS FIRST ROWS BETWEEN 1000000 PRECEDING
        AND CURRENT ROW
    ) AS po_min_cumulative
  FROM
    po_net
),
po_regulator AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    po_frontier,
    transfer_frontier,
    new_po,
    new_transfer,
    cumulative_demand,
    stock_remaining,
    allocated_from_stock,
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
po_shortage_delta AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    po_frontier,
    transfer_frontier,
    new_po,
    new_transfer,
    cumulative_demand,
    stock_remaining,
    allocated_from_stock,
    demand_after_stock,
    po_net_cumulative,
    po_min_cumulative,
    po_shortage_cumulative,
    po_shortage_cumulative - CASE
      WHEN LAG(po_shortage_cumulative, 1) OVER (
        PARTITION BY stream_key
        ORDER BY
          stream_key ASC NULLS FIRST,
          priority ASC NULLS FIRST,
          required_date ASC NULLS FIRST,
          document_id ASC NULLS FIRST
      ) IS NULL THEN 0
      ELSE LAG(po_shortage_cumulative, 1) OVER (
        PARTITION BY stream_key
        ORDER BY
          stream_key ASC NULLS FIRST,
          priority ASC NULLS FIRST,
          required_date ASC NULLS FIRST,
          document_id ASC NULLS FIRST
      )
    END AS demand_after_po
  FROM
    po_regulator
),
transfer_net AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    po_frontier,
    transfer_frontier,
    new_po,
    new_transfer,
    cumulative_demand,
    stock_remaining,
    allocated_from_stock,
    demand_after_stock,
    po_net_cumulative,
    po_min_cumulative,
    po_shortage_cumulative,
    demand_after_po,
    demand_after_stock - demand_after_po AS allocated_from_purchase_orders,
    po_net_cumulative + po_shortage_cumulative AS po_remaining,
    SUM(new_transfer - demand_after_po) OVER (
      PARTITION BY stream_key
      ORDER BY
        stream_key ASC NULLS FIRST,
        priority ASC NULLS FIRST,
        required_date ASC NULLS FIRST,
        document_id ASC NULLS FIRST ROWS UNBOUNDED PRECEDING
    ) AS transfer_net_cumulative
  FROM
    po_shortage_delta
),
transfer_min AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    po_frontier,
    transfer_frontier,
    new_po,
    new_transfer,
    cumulative_demand,
    stock_remaining,
    allocated_from_stock,
    demand_after_stock,
    po_net_cumulative,
    po_min_cumulative,
    po_shortage_cumulative,
    demand_after_po,
    allocated_from_purchase_orders,
    po_remaining,
    transfer_net_cumulative,
    MIN(transfer_net_cumulative) OVER (
      PARTITION BY stream_key
      ORDER BY
        stream_key ASC NULLS FIRST,
        priority ASC NULLS FIRST,
        required_date ASC NULLS FIRST,
        document_id ASC NULLS FIRST ROWS BETWEEN 1000000 PRECEDING
        AND CURRENT ROW
    ) AS transfer_min_cumulative
  FROM
    transfer_net
),
transfer_regulator AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    po_frontier,
    transfer_frontier,
    new_po,
    new_transfer,
    cumulative_demand,
    stock_remaining,
    allocated_from_stock,
    demand_after_stock,
    po_net_cumulative,
    po_min_cumulative,
    po_shortage_cumulative,
    demand_after_po,
    allocated_from_purchase_orders,
    po_remaining,
    transfer_net_cumulative,
    transfer_min_cumulative,
    CASE
      WHEN transfer_min_cumulative < 0 THEN 0 - transfer_min_cumulative
      ELSE 0
    END AS transfer_shortage_cumulative
  FROM
    transfer_min
),
shortage_delta AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    po_frontier,
    transfer_frontier,
    new_po,
    new_transfer,
    cumulative_demand,
    stock_remaining,
    allocated_from_stock,
    demand_after_stock,
    po_net_cumulative,
    po_min_cumulative,
    po_shortage_cumulative,
    demand_after_po,
    allocated_from_purchase_orders,
    po_remaining,
    transfer_net_cumulative,
    transfer_min_cumulative,
    transfer_shortage_cumulative,
    transfer_shortage_cumulative - CASE
      WHEN LAG(transfer_shortage_cumulative, 1) OVER (
        PARTITION BY stream_key
        ORDER BY
          stream_key ASC NULLS FIRST,
          priority ASC NULLS FIRST,
          required_date ASC NULLS FIRST,
          document_id ASC NULLS FIRST
      ) IS NULL THEN 0
      ELSE LAG(transfer_shortage_cumulative, 1) OVER (
        PARTITION BY stream_key
        ORDER BY
          stream_key ASC NULLS FIRST,
          priority ASC NULLS FIRST,
          required_date ASC NULLS FIRST,
          document_id ASC NULLS FIRST
      )
    END AS remaining_shortage
  FROM
    transfer_regulator
),
transfer_balance AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    po_frontier,
    transfer_frontier,
    new_po,
    new_transfer,
    cumulative_demand,
    stock_remaining,
    allocated_from_stock,
    demand_after_stock,
    po_net_cumulative,
    po_min_cumulative,
    po_shortage_cumulative,
    demand_after_po,
    allocated_from_purchase_orders,
    po_remaining,
    transfer_net_cumulative,
    transfer_min_cumulative,
    transfer_shortage_cumulative,
    remaining_shortage,
    demand_after_po - remaining_shortage AS allocated_from_transfers,
    transfer_net_cumulative + transfer_shortage_cumulative AS transfer_remaining
  FROM
    shortage_delta
),
projected_balance AS (
  SELECT
    document_id,
    stream_key,
    material_id,
    warehouse_id,
    demand_type,
    required_date,
    requested_qty,
    priority,
    usable_stock,
    compatibility_filter_seed,
    cumulative_po,
    cumulative_transfer,
    po_frontier,
    transfer_frontier,
    new_po,
    new_transfer,
    cumulative_demand,
    stock_remaining,
    allocated_from_stock,
    demand_after_stock,
    po_net_cumulative,
    po_min_cumulative,
    po_shortage_cumulative,
    demand_after_po,
    allocated_from_purchase_orders,
    po_remaining,
    transfer_net_cumulative,
    transfer_min_cumulative,
    transfer_shortage_cumulative,
    remaining_shortage,
    allocated_from_transfers,
    transfer_remaining,
    stock_remaining + po_remaining + transfer_remaining AS projected_stock_after_allocation
  FROM
    transfer_balance
)
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
FROM
  projected_balance;
