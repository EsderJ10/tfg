#!/usr/bin/env bash
# =============================================================================
# setup-cluster.sh — Cluster Kubernetes local con k3d (genérico)
#
# Comportamiento:
#   - Primera vez (post-create): instala k3d, crea el cluster, guarda kubeconfig.
#   - Siguientes arranques (post-start): si el cluster existe y está parado,
#     lo arranca y refresca el kubeconfig.
#   - Idempotente: nunca destruye datos existentes.
#
# Variables de entorno personalizables (tienen valores por defecto):
#   K3D_CLUSTER_NAME   nombre del cluster          (default: devcluster)
#   K3D_AGENTS         número de nodos worker      (default: 0 → solo server)
#   K3D_API_PORT       puerto del API server        (default: 6443)
#   K3D_LB_HTTP_PORT   puerto HTTP del load-balancer (default: 8080)
#   K3D_LB_HTTPS_PORT  puerto HTTPS del load-balancer (default: 8443)
#
# Kubeconfig:
#   Se guarda en $KUBECONFIG (definido en devcontainer.json/docker-compose).
#   Por defecto: /workspace/.devcontainer/.kube/config
#   Al estar dentro del bind-mount survives "Rebuild Container".
# =============================================================================
set -euo pipefail

# ── Variables ─────────────────────────────────────────────────────────────────
CLUSTER_NAME="${K3D_CLUSTER_NAME:-devcluster}"
AGENTS="${K3D_AGENTS:-0}"
API_PORT="${K3D_API_PORT:-6443}"
LB_HTTP_PORT="${K3D_LB_HTTP_PORT:-8080}"
LB_HTTPS_PORT="${K3D_LB_HTTPS_PORT:-8443}"
KUBECONFIG_PATH="${KUBECONFIG:-/workspace/.devcontainer/.kube/config}"

# ── Colores ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[k8s]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[k8s]${NC}  $*"; }
error() { echo -e "${RED}[k8s]${NC}  $*"; }

# ── Verifica que Docker socket es accesible ───────────────────────────────────
check_docker() {
  if ! docker info >/dev/null 2>&1; then
    error "Docker socket no accesible. Verifica que /var/run/docker.sock"
    error "está montado en el contenedor (docker-compose.yml)."
    exit 1
  fi
}

# ── Instala k3d si no está disponible ────────────────────────────────────────
install_k3d() {
  if command -v k3d >/dev/null 2>&1; then
    info "k3d $(k3d version | head -1) ya instalado."
    return 0
  fi
  info "Instalando k3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  info "k3d instalado: $(k3d version | head -1)"
}

# ── Crea el directorio del kubeconfig (dentro del bind-mount) ─────────────────
prepare_kubeconfig_dir() {
  local dir
  dir="$(dirname "${KUBECONFIG_PATH}")"
  mkdir -p "${dir}"
  chmod 700 "${dir}"
}

# ── Escribe/actualiza el kubeconfig ──────────────────────────────────────────
update_kubeconfig() {
  info "Actualizando kubeconfig en ${KUBECONFIG_PATH}..."
  k3d kubeconfig get "${CLUSTER_NAME}" > "${KUBECONFIG_PATH}"
  chmod 600 "${KUBECONFIG_PATH}"
  info "kubectl context activo: $(kubectl config current-context)"
}

# ── Crea el cluster (primera vez) ─────────────────────────────────────────────
create_cluster() {
  info "Creando cluster '${CLUSTER_NAME}'..."
  info "  Agents:     ${AGENTS}"
  info "  API port:   ${API_PORT}"
  info "  LB HTTP:    ${LB_HTTP_PORT}"
  info "  LB HTTPS:   ${LB_HTTPS_PORT}"

  k3d cluster create "${CLUSTER_NAME}" \
    --agents "${AGENTS}" \
    --api-port "${API_PORT}" \
    --port "${LB_HTTP_PORT}:80@loadbalancer" \
    --port "${LB_HTTPS_PORT}:443@loadbalancer" \
    --wait \
    --timeout 120s

  update_kubeconfig
  info "Cluster '${CLUSTER_NAME}' creado y listo."
  kubectl get nodes
}

# ── Arranca un cluster existente que está parado ──────────────────────────────
start_cluster() {
  info "Arrancando cluster '${CLUSTER_NAME}'..."
  k3d cluster start "${CLUSTER_NAME}" --wait --timeout 120s
  update_kubeconfig
  info "Cluster '${CLUSTER_NAME}' listo."
  kubectl get nodes
}

# ── Estado del cluster ────────────────────────────────────────────────────────
# Devuelve: "running", "stopped", "notfound"
cluster_state() {
  if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    echo "notfound"
    return
  fi
  # Si todos los nodos están en Running → running; si alguno está parado → stopped
  local running_nodes
  running_nodes=$(k3d cluster list 2>/dev/null | grep "^${CLUSTER_NAME}" | awk '{print $2}' | cut -d/ -f1)
  local total_nodes
  total_nodes=$(k3d cluster list 2>/dev/null | grep "^${CLUSTER_NAME}" | awk '{print $2}' | cut -d/ -f2)
  if [ "${running_nodes}" -ge 1 ] 2>/dev/null; then
    echo "running"
  else
    echo "stopped"
  fi
}

# ── Punto de entrada principal ────────────────────────────────────────────────
main() {
  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║   Kubernetes local (k3d)                             ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""

  check_docker
  install_k3d
  prepare_kubeconfig_dir

  local state
  state="$(cluster_state)"
  info "Estado del cluster '${CLUSTER_NAME}': ${state}"

  case "${state}" in
    notfound)
      create_cluster
      ;;
    stopped)
      start_cluster
      ;;
    running)
      info "Cluster '${CLUSTER_NAME}' ya está corriendo."
      update_kubeconfig
      kubectl get nodes
      ;;
  esac

  echo ""
  info "Para usar kubectl desde cualquier terminal del devcontainer:"
  info "  export KUBECONFIG=${KUBECONFIG_PATH}"
  info "  kubectl get pods -A"
  echo ""
}

main "$@"
