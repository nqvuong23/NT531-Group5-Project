import http from 'k6/http';
import { sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'ae7c044bf47bf4369abf4b6f5c7f44f9-21717f740aa40271.elb.ap-southeast-1.amazonaws.com';

const BURST_LEVELS = [200, 400, 600, 800];
const BURST_DURATION = 0.05; // 50ms
const SUSTAINED_RATE = 50;
const REST_TIME = 2;

export const options = {
  scenarios: {
    test: {
      executor: 'per-vu-iterations',
      vus: 50,
      iterations: 1,
    },
  },
};

function sendRequest() {
  http.get(BASE_URL);
}

// Warm-up 50 rps
function warmup() {
  const interval = 1 / SUSTAINED_RATE;

  const end = Date.now() + 30000;
  while (Date.now() < end) {
    sendRequest();
    sleep(interval);
  }
}

// Burst 50ms
function burst(rate) {
  const interval = 1 / rate;
  const end = Date.now() + BURST_DURATION * 1000;

  while (Date.now() < end) {
    sendRequest();
    sleep(interval);
  }
}

export default function () {
  // 1. Warm-up
  warmup();

  // 2. Random burst level
  const burstRate = BURST_LEVELS[Math.floor(Math.random() * BURST_LEVELS.length)];
  console.log(`🔥 Burst at ${burstRate} rps`);

  // 3. Burst
  burst(burstRate);

  // 4. Sustain sau burst
  sleep(REST_TIME);
}
