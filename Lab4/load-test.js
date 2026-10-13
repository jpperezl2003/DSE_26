import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';
import { Counter, Rate, Trend } from 'k6/metrics';

const BASE_URL = (__ENV.BASE_URL || 'http://dse-lab4-alb-763899916.us-east-1.elb.amazonaws.com').replace(/\/$/, '');
const MODE = __ENV.CACHE || 'on';
// Endpoints indicados por el usuario: producto 3 con cache y 2 sin cache.
const PRODUCT_ID = Number(__ENV.PRODUCT_ID || (MODE === 'on' ? 3 : 2));
const TARGET_URL = `${BASE_URL}/report?id=${PRODUCT_ID}&cache=${MODE}`;
const RPS = Number(__ENV.RPS || 10);
const LOG_REQUESTS = __ENV.LOG_REQUESTS === 'true';
if (!['on', 'off'].includes(MODE)) throw new Error('CACHE debe ser on u off');
if (!Number.isInteger(RPS) || RPS < 1) throw new Error('RPS debe ser un entero positivo');
if (!Number.isInteger(PRODUCT_ID) || PRODUCT_ID < 1 || PRODUCT_ID > 100) throw new Error('PRODUCT_ID debe estar entre 1 y 100');

// Estas metricas solo incluyen la carga medida, no el precalentamiento de setup.
const reportLatency = new Trend('report_latency', true);
const reportErrors = new Rate('report_errors');
const reportRequests = new Counter('report_requests');
const cacheHitRatio = new Rate('cache_hit_ratio');
const cacheHits = new Counter('cache_hits');
const cacheMisses = new Counter('cache_misses');
const cacheBypasses = new Counter('cache_bypasses');
const cacheCoalesced = new Counter('cache_coalesced');

export const options = {
  scenarios: {
    reports: {
      executor: 'constant-arrival-rate',
      rate: RPS,
      timeUnit: '1s',
      duration: '60s',
      preAllocatedVUs: 20,
      maxVUs: 50,
      gracefulStop: '15s',
    },
  },
  setupTimeout: '180s',
  summaryTrendStats: ['avg', 'min', 'max'],
  thresholds: {
    report_errors: ['rate<0.01'],
    dropped_iterations: ['count==0'],
  },
};

function payload(response) {
  try { return response.json(); } catch (_) { return null; }
}

function logRequest(label, response, body) {
  if (!LOG_REQUESTS) return;
  const cache = body && body.cache ? body.cache : 'ERROR';
  const lambdaMs = body && typeof body.elapsed_ms === 'number' ? body.elapsed_ms.toFixed(2) : 'N/A';
  console.log(`${label} | producto=${PRODUCT_ID} | HTTP=${response.status} | cache=${cache} | tiempo_http=${response.timings.duration.toFixed(2)}ms | lambda=${lambdaMs}ms${response.error ? ' | error=' + response.error : ''}`);
}

function validReport(response, body, id) {
  return response.status === 200 && body && body.data &&
    body.data.product_id === id && body.data.sales === 1000 &&
    (MODE === 'off' ? body.cache === 'BYPASS' : ['HIT', 'MISS', 'COALESCED'].includes(body.cache));
}

export function setup() {
  // Verifica la URL exacta y calienta cache/conexiones antes de medir.
  for (let i = 0; i < 3; i++) {
    const response = http.get(TARGET_URL, {
      timeout: '15s', tags: { name: 'warmup', phase: 'warmup' },
    });
    const body = payload(response);
    logRequest(`PRECALENTAMIENTO #${i + 1}`, response, body);
    if (!validReport(response, body, PRODUCT_ID)) {
      throw new Error(`Fallo en ${TARGET_URL}: HTTP ${response.status}. Revisa RDS y Lambda.`);
    }
    if (i === 2 && MODE === 'on' && body.cache !== 'HIT') {
      throw new Error('El endpoint con cache no confirma HIT despues del precalentamiento.');
    }
  }
  console.log(`Prueba ${TARGET_URL}, ${RPS} solicitudes/s, 60 segundos.`);
}

export default function () {
  const requestNumber = exec.scenario.iterationInTest + 1;
  const response = http.get(TARGET_URL, {
    timeout: '15s',
    tags: { name: 'report', phase: 'measured', cache_mode: MODE },
  });
  const body = payload(response);
  logRequest(`REQUEST #${requestNumber}`, response, body);
  const ok = Boolean(validReport(response, body, PRODUCT_ID));
  check(response, { 'HTTP 200 y reporte correcto': () => ok });
  reportRequests.add(1);
  reportLatency.add(response.timings.duration);
  reportErrors.add(!ok);
  cacheHitRatio.add(ok && body.cache === 'HIT');
  cacheHits.add(ok && body.cache === 'HIT' ? 1 : 0);
  cacheMisses.add(ok && body.cache === 'MISS' ? 1 : 0);
  cacheBypasses.add(ok && body.cache === 'BYPASS' ? 1 : 0);
  cacheCoalesced.add(ok && body.cache === 'COALESCED' ? 1 : 0);
  // No sleep: el executor controla la tasa de llegada.
}
