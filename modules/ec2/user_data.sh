#!/bin/bash
set -euo pipefail

#1. Install nginx
apt-get update -y
apt-get install -y nginx

# 2. Create the app's service account
useradd --system --create-home --home-dir /opt/sysdiag --shell /usr/sbin/nologin sysdiag

# 3. Get the code (as the app user, so it owns the files)
sudo -u sysdiag git clone https://github.com/Kishank00/linux-diagnostic-tool.git /opt/sysdiag/app


# 4. Install uv for the app user
sudo -u sysdiag -H bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'


# 5. Install dependencies from the lockfile into /opt/sysdiag/app/.venv
sudo -u sysdiag -H /opt/sysdiag/.local/bin/uv --directory /opt/sysdiag/app sync --locked --no-dev


# 6. Run the app as a systemd service
cat > /etc/systemd/system/sysdiag.service <<'EOF'
[Unit]
Description=Linux Diagnostic Tool API
After=network.target

[Service]
User=sysdiag
Group=sysdiag
WorkingDirectory=/opt/sysdiag/app
ExecStart=/opt/sysdiag/app/.venv/bin/uvicorn sysdiag.api.main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now sysdiag


# 7. nginx reverse proxy: port 80 -> app on 127.0.0.1:8000
cat > /etc/nginx/sites-available/sysdiag <<'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

ln -s /etc/nginx/sites-available/sysdiag /etc/nginx/sites-enabled/sysdiag
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
