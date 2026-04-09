#!/bin/bash
# =============================================================================
# post-create.sh — Inicialización del bench de Frappe (se ejecuta una sola vez)
#
# Este script se ejecuta automáticamente cuando VS Code crea o reconstruye
# el devcontainer (postCreateCommand). Es idempotente: si el bench ya existe
# (detectado por la presencia de Procfile), no hace nada.
#
# Persistencia garantizada:
#   - El bench vive en /workspace/frappe-bench → bind-montado desde el host →
#     sobrevive a "Rebuild Container".
#   - Los datos de MariaDB están en el volumen nombrado frappe-k8-mariadb-data →
#     también sobreviven a "Rebuild Container".
# =============================================================================
set -e

BENCH_DIR="/workspace/frappe-bench"
SITE_NAME="frappe_k8.localhost"
DB_ROOT_PASSWORD="123"
ADMIN_PASSWORD="123"
FRAPPE_BRANCH="version-16"

# ── Comprueba si el bench ya está inicializado ────────────────────────────────
if [ -f "${BENCH_DIR}/Procfile" ]; then
  echo "✅ Bench ya inicializado en ${BENCH_DIR}. Nada que hacer."
  exit 0
fi

# ── Limpia inicializaciones parciales (por si falló antes a medias) ──────────
if [ -d "${BENCH_DIR}" ]; then
  echo "⚠️  Directorio de bench parcial encontrado. Limpiando..."
  rm -rf "${BENCH_DIR}"
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   Frappe Bench — Primera inicialización              ║"
echo "║   Esto puede tardar 5-15 minutos (git clone + pip)   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Espera a que MariaDB esté lista (máx. 90 s) ──────────────────────────────
echo "⏳ Esperando a MariaDB..."
TRIES=0
until mysqladmin ping -h mariadb -u root -p"${DB_ROOT_PASSWORD}" --silent 2>/dev/null; do
  TRIES=$((TRIES + 1))
  if [ "${TRIES}" -ge 30 ]; then
    echo "❌ MariaDB no disponible después de 90 s. Abortando."
    exit 1
  fi
  printf "."
  sleep 3
done
echo ""
echo "✅ MariaDB lista."

# ── Inicializa el bench ───────────────────────────────────────────────────────
echo ""
echo "📦 Inicializando bench con Frappe ${FRAPPE_BRANCH}..."
bench init \
  --skip-redis-config-generation \
  --frappe-branch "${FRAPPE_BRANCH}" \
  "${BENCH_DIR}"

cd "${BENCH_DIR}"

# ── Apunta al stack de servicios Docker Compose (no localhost) ────────────────
echo ""
echo "🔧 Configurando conexiones a servicios Docker..."
bench set-config -g db_host mariadb
bench set-config -g redis_cache  "redis://redis-cache:6379"
bench set-config -g redis_queue  "redis://redis-queue:6379"
bench set-config -g redis_socketio "redis://redis-queue:6379"

# ── Crea el site ──────────────────────────────────────────────────────────────
echo ""
echo "🌐 Creando site: ${SITE_NAME}..."
bench new-site \
  --db-root-password "${DB_ROOT_PASSWORD}" \
  --admin-password   "${ADMIN_PASSWORD}"   \
  --mariadb-user-host-login-scope=% \
  "${SITE_NAME}"

# ── Activa el modo desarrollador ─────────────────────────────────────────────
echo ""
echo "🛠  Activando modo desarrollador..."
bench --site "${SITE_NAME}" set-config developer_mode 1
bench --site "${SITE_NAME}" clear-cache

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   ✅ Bench setup completado                          ║"
echo "║                                                      ║"
echo "║   Site:     ${SITE_NAME}         ║"
echo "║   URL:      http://${SITE_NAME}:8000  ║"
echo "║   Usuario:  Administrator                            ║"
echo "║   Password: ${ADMIN_PASSWORD}                                   ║"
echo "║                                                      ║"
echo "║   ℹ️  bench start se lanzará automáticamente via     ║"
echo "║      post-start.sh en cada arranque del contenedor.  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Configura el cluster Kubernetes local ─────────────────────────────────────
echo "⎈  Configurando cluster Kubernetes (k3d)..."
bash /workspace/.devcontainer/scripts/setup-cluster.sh
