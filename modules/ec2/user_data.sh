#!/bin/bash
set -euo pipefail

# 0. Wait for internet (max 30 tries, about 5 min): the NAT may still be starting on a fresh apply
tries=0
until curl -s --max-time 5 -o /dev/null https://github.com; do
  tries=$((tries + 1))
  if [ "$tries" -ge 30 ]; then
    echo "no internet after 30 tries, giving up"
    exit 1
  fi
  echo "waiting for internet... ($tries/30)"
  sleep 5
done

# 1. Install nginx and Docker
apt-get update -y
apt-get install -y nginx docker.io
systemctl enable --now docker

# 1b. Let Docker pull from ECR with the instance role (no docker login needed)
apt-get install -y amazon-ecr-credential-helper
mkdir -p /root/.docker
cat > /root/.docker/config.json <<'EOF'
{
  "credHelpers": {
    "286590629524.dkr.ecr.ap-south-1.amazonaws.com": "ecr-login"
  }
}
EOF

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

# 7. nginx reverse proxy: port 80 -> app on 127.0.0.1:8000, 8080 -> container on 127.0.0.1:8001
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

server {
    listen 8080;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8001;
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

# 8. Deploy script for future releases: pull, update deps, restart, health check
cat > /usr/local/bin/deploy-sysdiag <<'EOF'
#!/bin/bash
set -euo pipefail
sudo -u sysdiag git -C /opt/sysdiag/app pull --ff-only
sudo -u sysdiag -H /opt/sysdiag/.local/bin/uv --directory /opt/sysdiag/app sync --locked --no-dev
systemctl restart sysdiag
curl -fsS --retry 10 --retry-delay 2 --retry-connrefused http://localhost/health
EOF
chmod 755 /usr/local/bin/deploy-sysdiag

# 9. Deploy script for the Docker version: deploy-sysdiag-docker <image tag>
cat > /usr/local/bin/deploy-sysdiag-docker <<'EOF'
#!/bin/bash
set -euo pipefail
tag="${1:?usage: deploy-sysdiag-docker <image tag>}"
image="286590629524.dkr.ecr.ap-south-1.amazonaws.com/linux-diagnostic-tool:$tag"

docker pull "$image"
docker rm -f sysdiag || true
docker run -d --name sysdiag --restart unless-stopped -p 127.0.0.1:8001:8000 "$image"
curl -fsS --retry 10 --retry-delay 2 --retry-all-errors http://127.0.0.1:8001/health
EOF
chmod 755 /usr/local/bin/deploy-sysdiag-docker

# 10. Start the Docker version with its first image (later releases come from CI)
/usr/local/bin/deploy-sysdiag-docker 383aef87ffdb02fdd43b6e4bdadacc4aecafbc44

