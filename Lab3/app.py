"""Endpoint de carga del laboratorio; solo escucha en loopback tras Nginx.

Un worker de CPU, adecuado para la t2.micro (1 vCPU) de este laboratorio.
El trabajo es fijo: la petición no puede aumentar las iteraciones.
"""

import hashlib
import json
import socket
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

ITERATIONS = 200_000


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/compute":
            self.send_error(404)
            return

        started = time.perf_counter()
        digest = hashlib.pbkdf2_hmac(
            "sha256", b"lab3-workload", b"fixed-lab-salt", ITERATIONS
        )
        body = json.dumps({
            "hostname": socket.gethostname(),
            "iterations": ITERATIONS,
            "elapsed_ms": round((time.perf_counter() - started) * 1000, 2),
            "result": digest.hex(),
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # El cliente puede cancelar una petición durante la prueba.

    def log_message(self, *_args):
        pass  # Evita generar un registro por petición durante la carga.


class ComputeServer(HTTPServer):
    request_queue_size = 16

    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(5)
        return connection, address


if __name__ == "__main__":
    ComputeServer(("127.0.0.1", 8000), Handler).serve_forever()
