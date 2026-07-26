import http from 'k6/http';
import { check, group } from 'k6';
import { Rate } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';

const errorRate = new Rate('error_rate');

export const options = {
  vus: 1,
  iterations: 100,
  thresholds: {
    error_rate: ['rate<0.01'],
  },
};

export default function () {
  group('Rate Limiting', () => {
    let blocked = false;
    let successCount = 0;

    for (let i = 0; i < 100; i++) {
      const res = http.get(`${BASE_URL}/api/sum?term_one=1&term_two=${i}`);

      if (res.status === 429 && !blocked) {
        blocked = true;
        check(res, {
          'primeiro 429 retornado apos exceder limite': r => r.status === 429,
          'body do 429 contem error message': r => r.body && r.body.includes('Rate limit exceeded'),
        });
        errorRate.add(false);
      } else if (res.status === 200) {
        successCount++;
        errorRate.add(false);
      } else {
        errorRate.add(true);
      }
    }

    check(blocked, {
      'rate limit foi enforced (ao menos um 429)': b => b === true,
    });

    console.log(`Requests bem-sucedidos antes do bloqueio: ${successCount}`);
  });
}
