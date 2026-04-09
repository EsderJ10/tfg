#!/bin/bash
# =============================================================================
# post-start.sh — Arranque automático de servicios Frappe
#
# Se ejecuta CADA VEZ que el contenedor arranca (postStartCommand).
# Lanza "bench start" en background si el bench ya está inicializado.
# Es idempotente: no lanza un segundo proceso si ya hay uno corriendo.
#
# Dependencias externas (MariaDB y Redis) ya están arrancadas por
# Docker Compose antes de que este script se ejecute.
# =============================================================================

BENCH_DIR="/workspace/frappe-bench"
LOG_FILE="${BENCH_DIR}/logs/bench-start.log"

# ── El bench aún no fue inicializado (primera vez antes de post-create) ───────
if [ ! -f "${BENCH_DIR}/Procfile" ]; then
  echo "ℹ️  Bench no inicializado todavía. Se omite el arranque automático."
  echo "     postCreateCommand se encargará de la primera inicialización."
  exit 0
fi

# ── Evita arrancar un segundo proceso si bench ya está corriendo ─────────────
if pgrep -f "honcho start" > /dev/null 2>&1; then
  echo "ℹ️  Bench ya está corriendo (honcho detectado). No se lanza de nuevo."
  exit 0
fi

echo "🚀 Arrancando servicios de Frappe en background..."
cd "${BENCH_DIR}"
mkdir -p logs

# nohup + & → proceso independiente que no muere al salir el script
nohup bench start >> "${LOG_FILE}" 2>&1 &

echo "✅ Servicios arrancados."
echo "   Log:  ${LOG_FILE}"
echo "   URL:  http://frappe_k8.localhost:8000"
echo ""
echo "   Para ver los logs en tiempo real:"
echo "   tail -f ${LOG_FILE}"
echo ""
echo "   Para parar bench: pkill -f 'honcho start'"

# ── Arranca / reconcilia el cluster Kubernetes ────────────────────────────────
echo ""
echo "⎈  Verificando cluster Kubernetes (k3d)..."
bash /workspace/.devcontainer/scripts/setup-cluster.sh
