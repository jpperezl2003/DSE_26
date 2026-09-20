#!/bin/bash
set -e

dnf update -y
dnf install -y nginx

PRIVATE_IP=$(hostname -I | awk '{print $1}')
SERVER_NAME=$(hostname)

cat > /usr/share/nginx/html/index.html <<HTML
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Lab 2 · Balanceador AWS</title>
  <style>
    * { box-sizing: border-box; }

    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 24px;
      font-family: system-ui, sans-serif;
      color: #eef2ff;
      background:
        radial-gradient(ellipse at top left, #19345d, transparent 55%),
        #080e1b;
    }

    main {
      width: 100%;
      max-width: 680px;
      padding: clamp(28px, 6vw, 56px);
      background: #111c2eeF;
      border: 1px solid #2b3b53;
      border-radius: 28px;
      box-shadow: 0 24px 80px #0005;
    }

    .label {
      color: #7dd3fc;
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 3px;
      text-transform: uppercase;
    }

    h1 {
      margin: 20px 0 12px;
      font-size: clamp(32px, 6vw, 48px);
      line-height: 1.1;
      letter-spacing: -2px;
    }

    .intro {
      color: #a9b9cf;
      line-height: 1.7;
    }

    .server {
      margin: 32px 0;
      padding: 24px;
      border-radius: 18px;
      background: #080f1e;
      border: 1px solid #30425c;
    }

    .status {
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 13px;
      color: #86efac;
    }

    .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #4ade80;
      box-shadow: 0 0 12px #4ade8066;
    }

    .caption {
      margin: 24px 0 8px;
      color: #a9b9cf;
      font-size: 13px;
    }

    .ip {
      font-family: ui-monospace, monospace;
      font-size: clamp(24px, 5vw, 38px);
      font-weight: 700;
      color: #7dd3fc;
      overflow-wrap: anywhere;
    }

    .hostname {
      margin-top: 12px;
      color: #93a4bc;
      font-size: 12px;
      overflow-wrap: anywhere;
    }

    button {
      width: 100%;
      padding: 15px;
      border: 0;
      border-radius: 12px;
      background: #7dd3fc;
      color: #082033;
      font: inherit;
      font-weight: 700;
      cursor: pointer;
      transition: background .2s;
    }

    button:hover { background: #bae6fd; }
    button:focus-visible { outline: 3px solid white; outline-offset: 4px; }

    .note {
      color: #93a4bc;
      font-size: 12px;
      line-height: 1.6;
      text-align: center;
    }

    footer {
      margin-top: 32px;
      padding-top: 20px;
      border-top: 1px solid #2b3b53;
      color: #93a4bc;
      font-size: 12px;
      text-align: center;
    }
  </style>
</head>
<body>
  <main>
    <div class="label">Cloud Lab / 02</div>
    <h1>Una URL.<br>Dos servidores.</h1>
    <p class="intro">
      Esta página muestra la instancia EC2 que atendió
      tu petición a través del balanceador.
    </p>

    <section class="server">
      <div class="status">
        <span class="dot"></span>
        Respuesta recibida de Nginx
      </div>
      <div class="caption">IP privada del servidor</div>
      <div class="ip">${PRIVATE_IP}</div>
      <div class="hostname">Host: ${SERVER_NAME}</div>
    </section>

    <button onclick="window.location.replace(window.location.pathname + '?t=' + Date.now())">
      Enviar otra petición ↗
    </button>
    <p class="note">
      La siguiente petición puede responder desde la misma instancia.
    </p>

    <footer>AWS EC2 · Application Load Balancer · Terraform</footer>
  </main>
</body>
</html>
HTML

systemctl enable --now nginx