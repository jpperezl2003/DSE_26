CREATE DATABASE IF NOT EXISTS inventory;
CREATE TABLE IF NOT EXISTS inventory.raw_events (
    event_id String,
    rfid String,
    product_id String,
    warehouse_id String,
    movement Enum8('entrada' = 1, 'salida' = 2),
    occurred_at DateTime64(6, 'UTC'),
    ingested_at DateTime64(6, 'UTC') DEFAULT now64(6)
) ENGINE = ReplacingMergeTree(ingested_at) ORDER BY event_id;
CREATE OR REPLACE VIEW inventory.fact_movements AS
SELECT *, if(movement = 'entrada', 1, -1) AS quantity_delta
FROM inventory.raw_events FINAL;
CREATE OR REPLACE VIEW inventory.inventory_stock AS
SELECT warehouse_id, latest.2 AS product_id,
       countIf(latest.1 = 'entrada') AS stock, max(latest.3) AS updated_at
FROM (
    SELECT warehouse_id, rfid,
           argMax(tuple(movement, product_id, occurred_at), tuple(occurred_at, ingested_at, event_id)) AS latest
    FROM inventory.fact_movements GROUP BY warehouse_id, rfid
) GROUP BY warehouse_id, product_id;
CREATE OR REPLACE VIEW inventory.daily_movements AS
SELECT toDate(occurred_at) AS day, warehouse_id, product_id,
       countIf(movement = 'entrada') AS entries,
       countIf(movement = 'salida') AS exits,
       sum(quantity_delta) AS net_movement
FROM inventory.fact_movements GROUP BY day, warehouse_id, product_id;
CREATE USER IF NOT EXISTS ingestor IDENTIFIED WITH no_password HOST IP '10.50.0.0/16';
GRANT INSERT ON inventory.raw_events TO ingestor;
CREATE USER IF NOT EXISTS grafana_reader IDENTIFIED WITH no_password HOST LOCAL
SETTINGS readonly = 1, max_execution_time = 30 CHANGEABLE_IN_READONLY;
GRANT SELECT ON inventory.* TO grafana_reader;
