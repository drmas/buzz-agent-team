# Start agents on every boot (restart: on-failure alone doesn't survive a reboot reliably),
# and size memory limits for an 8 GB host.
set -euo pipefail
sed -i 's/mem_limit: 4g/mem_limit: 3g/' /opt/buzz-agents/compose.yml
cat > /etc/systemd/system/buzz-agents.service <<'UNIT'
[Unit]
Description=Buzz agent containers
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/buzz-agents
ExecStartPre=/opt/buzz-agents/refresh-secrets.sh
ExecStart=/usr/bin/docker compose -p buzz-agents up -d
ExecStop=/usr/bin/docker compose -p buzz-agents stop

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable buzz-agents.service 2>&1 | tail -1
grep mem_limit /opt/buzz-agents/compose.yml
