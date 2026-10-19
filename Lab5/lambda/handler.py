import base64
import json
import logging
import os
import urllib.parse
import urllib.request
from datetime import datetime, timezone

log = logging.getLogger()
log.setLevel(logging.INFO)
FIELDS = ("event_id", "rfid", "product_id", "warehouse_id", "movement", "timestamp")


def normalize(payload):
    if not isinstance(payload, dict):
        raise ValueError("Se requiere un objeto JSON")
    for field in FIELDS:
        value = payload.get(field)
        if not isinstance(value, str) or not value.strip() or len(value.encode("utf-8")) > 128:
            raise ValueError("Campo invalido: " + field)
    if payload["movement"] not in ("entrada", "salida"):
        raise ValueError("Movimiento invalido")
    instant = datetime.fromisoformat(payload["timestamp"].replace("Z", "+00:00"))
    if instant.tzinfo is None:
        raise ValueError("Timestamp requiere zona horaria")
    row = {key: payload[key] for key in FIELDS if key != "timestamp"}
    row["occurred_at"] = instant.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")
    return row


def insert_batch(rows, context):
    # Fixed SQL; event values are encoded as JSONEachRow, never interpolated into SQL.
    params = urllib.parse.urlencode({
        "query": "INSERT INTO inventory.raw_events FORMAT JSONEachRow",
        "wait_end_of_query": "1",
    })
    data = ("\n".join(json.dumps(row, ensure_ascii=False) for row in rows) + "\n").encode()
    request = urllib.request.Request(os.environ["CLICKHOUSE_URL"].rstrip("/") + "/?" + params,
        data=data, method="POST", headers={
            "X-ClickHouse-User": "ingestor", "Content-Type": "application/x-ndjson"})
    with urllib.request.urlopen(request, timeout=15) as response:
        body = response.read()
        if body.strip():
            raise RuntimeError("ClickHouse returned an unexpected insert response")
    log.info("Guardados %s eventos en ClickHouse", len(rows))


def lambda_handler(event, context):
    rows = []
    for record in event["Records"]:
        try:
            payload = json.loads(base64.b64decode(record["kinesis"]["data"]))
            rows.append(normalize(payload))
        except (ValueError, TypeError, KeyError):
            log.exception("Lectura invalida descartada: %s", record.get("eventID"))
    if rows:
        try:
            insert_batch(rows, context)
        except Exception:
            log.exception("Lote no confirmado; se reintentara")
            return {"batchItemFailures": [{"itemIdentifier": event["Records"][0]["kinesis"]["sequenceNumber"]}]}
    return {"batchItemFailures": []}
