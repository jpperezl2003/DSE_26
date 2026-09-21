import http from 'k6/http';
import { check } from 'k6';

const baseURL = (__ENV.BASE_URL || '').replace(/\/$/, '');
if (!/^https?:\/\/[^/]+$/.test(baseURL)) {
  throw new Error('Indica BASE_URL con la URL raiz del ALB, sin rutas.');
}
const rate = Number(__ENV.RATE || 30);
if (!Number.isInteger(rate) || rate < 1 || rate > 200) {
  throw new Error('RATE debe ser un entero entre 1 y 200 peticiones por segundo.');
}

export const options = {
  scenarios: {
    cpu_load: {
      executor: 'ramping-arrival-rate',
      startRate: 1,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 200,
      stages: [
        { duration: '1m', target: rate },
        { duration: '8m', target: rate },
        { duration: '1m', target: 0 },
      ],
      gracefulStop: '15s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    checks: ['rate>0.95'],
  },
};

export function setup() {
  const response = http.get(`${baseURL}/compute`, { timeout: '10s' });
  if (response.status !== 200 || response.json('iterations') !== 200000) {
    throw new Error('El endpoint /compute no esta listo; revisa despliegue y acceso al ALB.');
  }
}

export default function () {
  const response = http.get(`${baseURL}/compute`, {
    timeout: '10s',
    tags: { name: 'compute' },
  });
  check(response, { 'compute responde 200': (r) => r.status === 200 });
}
