#!/usr/bin/env bash
# launchd wrapper — keeps K8s port-forward + HTTP service alive
set -euo pipefail

PROJECT_DIR="/Users/brandon.shi/Documents/gitlab/agentdatatransfer"
LOG="/tmp/agent-launchd.log"

echo "[$(date)] agentdatatransfer launchd starting" >> "$LOG"

# ensure kubectl context is fat
kubectl config use-context fat &>/dev/null

# restart port-forwards if they die
while true; do
  if ! lsof -i :6580 &>/dev/null; then
    kubectl port-forward svc/cooperation -n ecir-app 6580:9090 &>/dev/null &
    echo "[$(date)] port-forward :6580 started" >> "$LOG"
  fi
  if ! lsof -i :6570 &>/dev/null; then
    kubectl port-forward svc/compliance -n ecir-app 6570:9090 &>/dev/null &
    echo "[$(date)] port-forward :6570 started" >> "$LOG"
  fi
  sleep 30
done
