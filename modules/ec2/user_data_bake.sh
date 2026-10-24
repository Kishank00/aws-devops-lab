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

# 2. Bring the VM app from the code baked into the AMI up to the latest master
/usr/local/bin/deploy-sysdiag

# 3. Start the Docker version with the live image tag from Parameter Store
tag=$(/snap/bin/aws ssm get-parameter \
  --region ap-south-1 \
  --name /devops-lab-dev/sysdiag/image-tag \
  --query Parameter.Value --output text)
/usr/local/bin/deploy-sysdiag-docker "$tag"
