"""ALB -> Lambda -> Redis cache-aside -> PostgreSQL; datos sinteticos."""
import json
import os
from pathlib import Path
import random
import ssl
import time
import uuid

import pg8000.dbapi
import redis

CACHE = redis.Redis(
    host=os.environ["CACHE_HOST"], port=6379,
    password=os.environ["CACHE_TOKEN"], ssl=True,
    decode_responses=True, socket_connect_timeout=1, socket_timeout=1,
    max_connections=2,
)
TTL = int(os.environ.get("CACHE_TTL", "300"))
UNLOCK = "if redis.call('get',KEYS[1]) == ARGV[1] then return redis.call('del',KEYS[1]) else return 0 end"


def connect(timeout=5):
    # Una conexion por consulta; se cierra incluso con errores para evitar
    # conexiones ociosas de entornos Lambda congelados en la pequena RDS.
    context = ssl.create_default_context()
    context.load_verify_locations(cafile=os.path.join(os.path.dirname(__file__), "rds-ca.pem"))
    connection = pg8000.dbapi.connect(
        host=os.environ["DB_HOST"], database=os.environ["DB_NAME"],
        user=os.environ["DB_USER"], password=os.environ["DB_PASSWORD"],
        ssl_context=context, timeout=timeout,
    )
    connection.autocommit = True
    return connection


def seed():
    connection = connect(timeout=60)
    try:
        cursor = connection.cursor()
        sql = Path(__file__).with_name("seed.sql").read_text(encoding="utf-8")
        cursor.execute(sql)
        cursor.execute("SELECT count(*), count(DISTINCT product_id) FROM sales")
        sales, products = cursor.fetchone()
        return {"sales": sales, "products": products}
    finally:
        connection.close()


def query(product):
    connection = connect()
    try:
        cursor = connection.cursor()
        cursor.execute("SET statement_timeout = '4000ms'")
        cursor.execute("SELECT count(*), sum(amount), avg(amount) FROM sales WHERE product_id = %s", (product,))
        count, total, average = cursor.fetchone()
        return {"product_id": product, "sales": count, "total_cents": total, "average_cents": float(average) if average is not None else None}
    finally:
        connection.close()


def read(product, bypass=False):
    if bypass:
        return query(product), "BYPASS"
    key = f"lab4:report:v1:{product}"
    lock = key + ":lock"
    token = uuid.uuid4().hex
    try:
        cached = CACHE.get(key)
        if cached is not None:
            return json.loads(cached), "HIT"
        # Evita que todos los MISS del mismo producto consulten RDS a la vez.
        owner = CACHE.set(lock, token, nx=True, ex=12)
        if not owner:
            deadline = time.monotonic() + 6
            while time.monotonic() < deadline:
                time.sleep(0.05)
                cached = CACHE.get(key)
                if cached is not None:
                    return json.loads(cached), "COALESCED"
            raise TimeoutError("cache fill timeout")
    except redis.RedisError:
        # Fallo cerrado para proteger la pequena RDS de una avalancha.
        raise TimeoutError("cache unavailable") from None
    try:
        # Revisa de nuevo por si otro escritor termino antes del lock.
        cached = CACHE.get(key)
        if cached is not None:
            return json.loads(cached), "HIT"
        value = query(product)
        CACHE.set(key, json.dumps(value), ex=TTL + random.randint(0, 30))
        return value, "MISS"
    finally:
        try:
            CACHE.eval(UNLOCK, 1, lock, token)
        except redis.RedisError:
            pass  # El lock tambien expira.


def response(code, payload, cache="NONE"):
    return {
        "statusCode": code,
        "isBase64Encoded": False,
        "headers": {"content-type": "application/json", "x-cache": cache, "cache-control": "no-store"},
        "body": json.dumps(payload),
    }


def handler(event, context):
    started = time.perf_counter()
    # Administracion solo por InvokeFunction IAM; nunca por una ruta ALB.
    if "requestContext" not in event and event.get("action") == "seed":
        return seed()
    if "requestContext" not in event and event.get("action") == "clear":
        keys = [f"lab4:report:v1:{i}" for i in range(1, 101)]
        return {"deleted": CACHE.delete(*keys)}
    if event.get("httpMethod") != "GET":
        return response(405, {"error": "GET required"})
    if event.get("path") == "/health":
        return response(200, {"status": "ok"})
    if event.get("path") != "/report":
        return response(404, {"error": "use /report?id=1&cache=on"})
    params = event.get("queryStringParameters") or {}
    try:
        product = int(params.get("id", "1"))
        mode = params.get("cache", "on")
        if not 1 <= product <= 100 or mode not in ("on", "off"):
            raise ValueError()
    except (ValueError, TypeError):
        return response(400, {"error": "id: 1..100; cache: on|off"})
    try:
        value, cache = read(product, bypass=mode == "off")
        elapsed = round((time.perf_counter() - started) * 1000, 3)
        print(json.dumps({"cache": cache, "elapsed_ms": elapsed, "product_id": product}))
        return response(200, {"data": value, "cache": cache, "elapsed_ms": elapsed}, cache)
    except Exception as error:
        print(json.dumps({"error_type": type(error).__name__, "product_id": product}))
        return response(503, {"error": "temporarily unavailable"}, "ERROR")
