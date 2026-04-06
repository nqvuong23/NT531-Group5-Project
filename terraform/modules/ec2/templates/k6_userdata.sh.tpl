#!/bin/bash
set -euo pipefail

# ============================================================
# User Data Script: K6 Load Testing Instance
# Project: ${project_name}
# ============================================================

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "=== Starting K6 instance setup at $(date) ==="

# Cập nhật hệ thống
yum update -y

# Cài đặt các công cụ cơ bản
yum install -y \
  curl \
  wget \
  git \
  jq \
  htop \
  unzip \
  awscli

# Cài đặt K6
echo "=== Installing K6 v${k6_version} ==="
wget -q "https://github.com/grafana/k6/releases/download/v${k6_version}/k6-v${k6_version}-linux-amd64.tar.gz" \
  -O /tmp/k6.tar.gz

tar -xzf /tmp/k6.tar.gz -C /tmp/
mv "/tmp/k6-v${k6_version}-linux-amd64/k6" /usr/local/bin/k6
chmod +x /usr/local/bin/k6

# Kiểm tra cài đặt
k6 version

# Tạo thư mục làm việc cho K6 scripts
mkdir -p /home/ec2-user/k6-scripts
chown ec2-user:ec2-user /home/ec2-user/k6-scripts

# Tạo script K6 mẫu
cat > /home/ec2-user/k6-scripts/basic-load-test.js << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';

// Cấu hình load test
export const options = {
  stages: [
    { duration: '1m', target: 10 },   // Ramp up
    { duration: '3m', target: 50 },   // Stay at 50 VUs
    { duration: '1m', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const response = http.get(__ENV.TARGET_URL || 'http://localhost');
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  sleep(1);
}
EOF

chown ec2-user:ec2-user /home/ec2-user/k6-scripts/basic-load-test.js

echo "=== K6 setup completed at $(date) ==="
echo "=== K6 version: $(k6 version) ==="
