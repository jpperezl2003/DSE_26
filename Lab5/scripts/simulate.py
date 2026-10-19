import argparse
import json
import random
import time
import uuid
from datetime import datetime, timezone

import boto3

parser = argparse.ArgumentParser(description="Simula lecturas RFID de inventario")
parser.add_argument("--stream", required=True)
parser.add_argument("--region", default="us-east-1")
parser.add_argument("--interval", type=float, default=2)
parser.add_argument("--events", type=int, default=20)
args = parser.parse_args()
if args.interval < 0 or args.events < 1:
    parser.error("interval debe ser >= 0 y events >= 1")
client = boto3.client("kinesis", region_name=args.region)
present = set()
# Unique run prefix prevents RFID collisions between simulator runs.
run = uuid.uuid4().hex[:12]
for i in range(args.events):
    if present and random.random() < 0.4:
        rfid, product = random.choice(tuple(present))
        present.remove((rfid, product))
        movement = "salida"
    else:
        product = random.choice(["LAPTOP", "MONITOR", "TECLADO", "MOUSE"])
        rfid = f"{run}-{i:05d}"
        present.add((rfid, product))
        movement = "entrada"
    event = {
        "event_id": str(uuid.uuid4()), "rfid": rfid,
        "product_id": product, "warehouse_id": "almacen-01",
        "movement": movement,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    client.put_record(StreamName=args.stream, Data=json.dumps(event).encode(),
                      PartitionKey=f"almacen-01#{product}")
    print(json.dumps(event), flush=True)
    time.sleep(args.interval)
