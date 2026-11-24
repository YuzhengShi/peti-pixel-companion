#!/bin/bash
set -euo pipefail
exec > /var/log/peti-setup.log 2>&1

# ── Secrets ──
# No secret is stored in this file. When the script is run by hand, each value
# can be passed in the environment (letters and digits only); otherwise, as under
# EC2 user data, a random value is generated here and kept only in
# /opt/peti/api/.env (mode 600).
DB_PASSWORD="${PETI_DB_PASSWORD:-$(openssl rand -hex 32)}"
JWT_SECRET="${PETI_JWT_SECRET:-$(openssl rand -hex 32)}"
INTERNAL_SECRET="${PETI_INTERNAL_SECRET:-$(openssl rand -hex 32)}"

# ── System packages ──
apt-get update -y
apt-get install -y docker.io git nginx postgresql postgresql-contrib

# Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# ── Start Docker ──
systemctl enable docker --now
usermod -aG docker ubuntu

# ── PostgreSQL ──
systemctl enable postgresql --now
sudo -u postgres psql -c "CREATE USER peti WITH PASSWORD '${DB_PASSWORD}';"
sudo -u postgres psql -c "CREATE DATABASE peti OWNER peti;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE peti TO peti;"

# ── Clone repo ──
cd /opt
git clone https://github.com/YuzhengShi/Peti.git peti || true
cd /opt/peti

# ── API setup ──
cd /opt/peti/api
npm install

install -m 600 /dev/null .env
cat > .env << ENVEOF
DATABASE_URL=postgresql://peti:${DB_PASSWORD}@localhost:5432/peti
JWT_SECRET=${JWT_SECRET}
OPENWEATHERMAP_API_KEY=
FRONTEND_URL=http://localhost
PORT=3001
NODE_ENV=production
INTERNAL_SECRET=${INTERNAL_SECRET}
CONTAINER_IMAGE=peti-agent:latest
AGENT_CHARACTER_DIR=/opt/peti/agent/character
FRAMEWORK_DIR=/opt/peti/docs/framework
BACKEND_URL=http://host.docker.internal:3001
AWS_DEFAULT_REGION=us-west-2
ENVEOF

npx prisma generate
npx prisma migrate deploy
npm run build

# ── Client build ──
cd /opt/peti/client
npm install
npm run build

# ── Build Docker agent image ──
cd /opt/peti/agent/container
docker build -t peti-agent:latest .

# ── Nginx config ──
cat > /etc/nginx/sites-available/peti << 'NGINXEOF'
server {
    listen 80;
    server_name _;

    root /opt/peti/client/dist;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 86400;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/peti /etc/nginx/sites-enabled/peti
rm -f /etc/nginx/sites-enabled/default
systemctl enable nginx --now
systemctl restart nginx

# ── Systemd service for API ──
cat > /etc/systemd/system/peti-api.service << 'SVCEOF'
[Unit]
Description=Peti API
After=network.target postgresql.service docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/peti/api
ExecStart=/usr/bin/node dist/index.js
Restart=on-failure
RestartSec=5
EnvironmentFile=/opt/peti/api/.env

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable peti-api --now

echo "=== Peti deployment complete ==="
