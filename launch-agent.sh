#!/usr/bin/env bash
set -euo pipefail
LOG="/tmp/agent-startup.log"
KUBECTL="/opt/homebrew/bin/kubectl"
PROJECT="/Users/brandon.shi/Documents/gitlab/agentdatatransfer"
BINARY="$PROJECT/build/company_oss_file_service"

echo "[$(date)] agentdatatransfer daemon started" > "$LOG"

# ensure K8s context
$KUBECTL config use-context fat &>/dev/null

# clean stale processes
pkill -f "kubectl port-forward.*6580" 2>/dev/null || true
pkill -f "kubectl port-forward.*6570" 2>/dev/null || true
pkill -f company_oss_file_service 2>/dev/null || true
sleep 1

# start the service
cd "$PROJECT"
set -a && [ -f .env ] && . ./.env && set +a
nohup "$BINARY" &>/tmp/svc.log &
echo "[$(date)] HTTP service started" >> "$LOG"

# keep port-forwards alive
while true; do
  if ! lsof -i :6580 &>/dev/null; then
    $KUBECTL port-forward svc/cooperation -n ecir-app 6580:9090 &>/tmp/pf-coop.log &
    echo "[$(date)] port-forward :6580 reconnected" >> "$LOG"
  fi
  if ! lsof -i :6570 &>/dev/null; then
    $KUBECTL port-forward svc/compliance -n ecir-app 6570:9090 &>/tmp/pf-comp.log &
    echo "[$(date)] port-forward :6570 reconnected" >> "$LOG"
  fi
  sleep 15
done
