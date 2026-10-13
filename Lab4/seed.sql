-- Datos sinteticos del Lab4: 100,000 ventas para 100 productos.
-- Puede ejecutarse nuevamente sin duplicar las ventas existentes.
BEGIN;

CREATE TABLE IF NOT EXISTS sales (
    id integer PRIMARY KEY,
    product_id integer NOT NULL,
    amount integer NOT NULL
);

-- amount representa el importe en centavos.
INSERT INTO sales (id, product_id, amount)
SELECT n, ((n - 1) % 100) + 1, ((n * 17) % 10000) + 100
FROM generate_series(1, 100000) AS n
ON CONFLICT (id) DO NOTHING;

CREATE INDEX IF NOT EXISTS sales_product_idx ON sales (product_id);
ANALYZE sales;

COMMIT;
