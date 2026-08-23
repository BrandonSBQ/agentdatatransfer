#!/usr/bin/env bash
# 一键启动所有服务
set -euo pipefail
cd "$(dirname "$0")"

echo "=== 清理旧进程 ==="
pkill -f "kubectl port-forward" 2>/dev/null || true
pkill -f company_oss_file_service 2>/dev/null || true
sleep 1

echo "=== K8s 端口映射 ==="
K8S_CONTEXT=${K8S_CONTEXT:-fat}
kubectl config use-context "$K8S_CONTEXT" &>/dev/null
nohup kubectl port-forward svc/cooperation -n ecir-app 6580:9090 &>/tmp/pf-coop.log 2>&1 &
disown
nohup kubectl port-forward svc/cooperation -n ecir-app 2020:9090 &>/tmp/pf-coop-2020.log 2>&1 &
disown
nohup kubectl port-forward svc/compliance -n ecir-app 6570:9090 &>/tmp/pf-comp.log 2>&1 &
disown
nohup kubectl port-forward svc/foundation -n rd-platform 7020:9090 &>/tmp/pf-foundation.log 2>&1 &
disown
nohup kubectl port-forward svc/screening -n aml-app 7080:9090 &>/tmp/pf-screening.log 2>&1 &
disown
sleep 2

echo "=== 启动 HTTP 服务 ==="
set -a && [ -f .env ] && . ./.env && set +a
nohup ./build/company_oss_file_service &>/tmp/svc.log 2>&1 &
disown
sleep 2

curl -sf http://127.0.0.1:7070/healthy && echo "" && echo "✅ 服务已启动  http://127.0.0.1:8080" || echo "❌ 启动失败, 查看 /tmp/svc.log"
