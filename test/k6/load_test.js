import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';

const errorRate = new Rate('error_rate');

export const options = {
  stages: [
    { duration: '10s', target: 2 },
    { duration: '20s', target: 2 },
    { duration: '10s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    error_rate: ['rate<0.01'],
  },
};

function callAndCheck(name, path, expected) {
  const res = http.get(`${BASE_URL}${path}`);
  const ok = check(res, { [`${name} status ${expected}`]: r => r.status === expected });
  errorRate.add(!ok);
}

export default function () {
  group('Happy Path', () => {
    [
      ['sum',        '/api/sum?term_one=4&term_two=2',         200],
      ['sub',        '/api/sub?term_one=10&term_two=3',        200],
      ['mul',        '/api/mul?term_one=3&term_two=5',         200],
      ['div',        '/api/div?term_one=10&term_two=2',        200],
      ['healthz',    '/healthz/ready',                          200],
      ['liveness',   '/healthz/live',                           200],
    ].forEach(([name, path, expected]) => callAndCheck(name, path, expected));
  });

  group('Error Cases', () => {
    [
      ['div by zero',    '/api/div?term_one=10&term_two=0',     400],
      ['missing params', '/api/sum',                             400],
      ['invalid param',  '/api/sum?term_one=abc&term_two=2',    400],
      ['missing one',    '/api/sub?term_one=5',                  400],
    ].forEach(([name, path, expected]) => callAndCheck(name, path, expected));
  });

  sleep(1);
}
