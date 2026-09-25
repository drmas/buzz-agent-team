#!/bin/bash
# EC2 first-boot: Docker Engine + Compose (official apt repo), Buzz checkout, agent scaffold.
set -euxo pipefail
exec > >(tee /var/log/buzz-bootstrap.log) 2>&1

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git openssl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

git clone --depth 1 https://github.com/block/buzz.git /opt/buzz

# Agent scaffold (relay-only for now; add agents later with add-agent.sh).
install -d -m 0700 /opt/buzz-agents
cat > /opt/buzz-agents/Dockerfile <<'EOF'
FROM ghcr.io/block/buzz-sprig:sha-6530b58@sha256:17facfc7608d8ddb33bc056c9aaba1098f4ef6abe5655702fbfd7584d1f74d76
USER root
RUN apk add --no-cache nodejs npm && npm i -g @agentclientprotocol/claude-agent-acp
USER agent
EOF

touch /var/lib/buzz-bootstrap-done
