#!/usr/bin/env bash
# Kubeport eval-stack entrypoint.
#
# Idempotent: safe to run on every container start.  Steps:
#   1. Wait for MariaDB and the two Redis services to accept connections.
#   2. Wait for k3s to write its kubeconfig to the shared /shared/k3s volume.
#   3. Patch common_site_config.json so the bench points at the compose
#      services (mariadb, redis-cache:6379, redis-queue:6379) instead of
#      127.0.0.1.
#   4. On first run only, create the eval site and install the kubeport app.
#   5. On first run only, seed a Kubernetes Cluster row pointing at k3s.
#   6. exec the supplied command (default: `bench start`).

set -euo pipefail

BENCH_DIR="${BENCH_DIR:-/home/frappe/kubeport-bench}"
SITE_NAME="${SITE_NAME:-kubeport.localhost}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
MARIADB_HOST="${MARIADB_HOST:-mariadb}"
MARIADB_PORT="${MARIADB_PORT:-3306}"
MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-changeme}"
REDIS_CACHE="${REDIS_CACHE:-redis://redis-cache:6379}"
REDIS_QUEUE="${REDIS_QUEUE:-redis://redis-queue:6379}"
K3S_KUBECONFIG="${K3S_KUBECONFIG:-/shared/k3s/kubeconfig.yaml}"
K3S_CLUSTER_NAME="${K3S_CLUSTER_NAME:-eval-k3s}"

log() { printf '[entrypoint] %s\n' "$*"; }

wait_for_tcp() {
    local host="$1" port="$2" label="${3:-$host:$port}"
    log "waiting for ${label}"
    for i in $(seq 1 120); do
        if (echo > "/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
            log "${label} reachable"
            return 0
        fi
        sleep 2
    done
    log "ERROR: ${label} not reachable after 240s"
    return 1
}

wait_for_kubeconfig() {
    log "waiting for k3s kubeconfig at ${K3S_KUBECONFIG}"
    for i in $(seq 1 120); do
        if [ -s "${K3S_KUBECONFIG}" ]; then
            log "kubeconfig present"
            return 0
        fi
        sleep 2
    done
    log "WARNING: kubeconfig not found after 240s; proceeding without seeded cluster"
    return 1
}

cd "${BENCH_DIR}"

wait_for_tcp "${MARIADB_HOST}" "${MARIADB_PORT}" "mariadb"
wait_for_tcp "redis-cache" "6379" "redis-cache"
wait_for_tcp "redis-queue" "6379" "redis-queue"

# Point the bench at the docker-compose services.  bench set-* commands rewrite
# sites/common_site_config.json in place; idempotent across restarts.
log "wiring bench to compose services"
bench set-mariadb-host "${MARIADB_HOST}"
bench set-redis-cache-host "${REDIS_CACHE}"
bench set-redis-queue-host "${REDIS_QUEUE}"
bench set-redis-socketio-host "${REDIS_QUEUE}"
bench set-config -g db_port "${MARIADB_PORT}"
bench set-config -g developer_mode 0

# First-run site init.  We can't bake this into the image because new-site
# needs a live MariaDB to install the framework schema.
if [ ! -f "sites/${SITE_NAME}/site_config.json" ]; then
    log "creating site ${SITE_NAME} (one-time, ~60s)"
    bench new-site \
        --mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
        --admin-password "${ADMIN_PASSWORD}" \
        --no-mariadb-socket \
        --install-app kubeport \
        "${SITE_NAME}"
    bench use "${SITE_NAME}"
    log "site ${SITE_NAME} ready (admin password: ${ADMIN_PASSWORD})"
else
    log "site ${SITE_NAME} already exists, skipping init"
fi

# Seed the Kubernetes Cluster row pointing at the embedded k3s.  Idempotent —
# the script no-ops when the row already exists.  Skipped if k3s never came up
# so the bench still serves; the operator can connect a cluster manually.
#
# We invoke the script through the bench venv's Python directly (rather than
# `bench execute`) so the file's location does not have to be on the bench
# import path; the script handles its own frappe.init / frappe.connect.
if wait_for_kubeconfig; then
    log "seeding Kubernetes Cluster row '${K3S_CLUSTER_NAME}'"
    "${BENCH_DIR}/env/bin/python" /home/frappe/seed_default_cluster.py \
        --site "${SITE_NAME}" \
        --cluster-name "${K3S_CLUSTER_NAME}" \
        --kubeconfig "${K3S_KUBECONFIG}" \
        || log "seed_default_cluster failed (non-fatal — connect a cluster from the UI)"
fi

# bench start runs honcho across web (gunicorn), worker (rq), and scheduler.
# Ports: 8000 (web), 9000 (socketio).
log "starting bench: $*"
exec "$@"
