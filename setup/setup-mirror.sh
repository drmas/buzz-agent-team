# Runs on the instance: nightly memory mirror + handoff cleanup (systemd timer) + one immediate run.
set -euo pipefail
cat > /etc/systemd/system/buzz-memory-mirror.service <<'UNIT'
[Unit]
Description=Mirror Buzz agents' file memory into their Buzz memory; prune old file handoffs
Requires=docker.service
After=docker.service buzz-agents.service

[Service]
Type=oneshot
WorkingDirectory=/opt/buzz-agents
ExecStart=/opt/buzz-agents/agentctl mirror
ExecStart=/opt/buzz-agents/agentctl prune-exchange 30
UNIT
cat > /etc/systemd/system/buzz-memory-mirror.timer <<'UNIT'
[Unit]
Description=Nightly Buzz agent memory mirror

[Timer]
OnCalendar=*-*-* 02:00:00 UTC
Persistent=true
RandomizedDelaySec=10m

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now buzz-memory-mirror.timer 2>&1 | tail -1
systemctl list-timers buzz-memory-mirror.timer --no-pager | sed -n 1,2p
echo "== first run"
agentctl mirror
echo "== what Buzz now holds (pm)"
cd /opt/buzz-agents && docker compose -p buzz-agents exec -T pm sh -c 'buzz mem ls; echo; buzz mem get core; echo; ls ~/memory' </dev/null 2>&1 | head -20
echo "== second run (should push nothing)"
agentctl mirror pm
