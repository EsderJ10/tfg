# Kubeport eval image — Frappe v16 bench with helm CLI and kubeport baked in.
#
# Build (from tfg/deploy):
#   docker compose build kubeport
# or:
#   docker build -t kubeport-eval:latest -f images/kubeport/Dockerfile .
#
# The build:
#   1. Initialises a Frappe v16 bench at /home/frappe/kubeport-bench.
#   2. Pulls the Kubeport app at $KUBEPORT_REF and registers it on the bench.
#   3. Adds the helm 3 CLI to /usr/local/bin/helm.
# Site creation (`bench new-site` + `bench install-app kubeport`) runs on first
# container start because it needs a live MariaDB. See entrypoint.sh.

# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=docker.io/frappe/bench:latest
ARG HELM_VERSION=v3.16.4

FROM alpine:3 AS helm
ARG HELM_VERSION
RUN apk add --no-cache curl tar \
 && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    | tar -xz -C /tmp \
 && install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm \
 && /usr/local/bin/helm version --short

FROM ${BASE_IMAGE} AS bench

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        netcat-openbsd \
 && rm -rf /var/lib/apt/lists/*

COPY --from=helm /usr/local/bin/helm /usr/local/bin/helm
RUN chmod 0755 /usr/local/bin/helm && /usr/local/bin/helm version --short

USER frappe
WORKDIR /home/frappe

# bench init clones Frappe at version-16 and pip-installs it into a venv.
# --skip-redis-config-generation lets us point the bench at the docker-compose
# redis services through common_site_config.json instead of bench-managed redis.
RUN bench init \
        --frappe-branch version-16 \
        --skip-redis-config-generation \
        --no-backups \
        kubeport-bench

WORKDIR /home/frappe/kubeport-bench

# Pin the Kubeport revision the eval stack ships against.  The submission
# branch can pin this to a frozen tag; main is the default for development.
ARG KUBEPORT_REPO=https://github.com/EsderJ10/kubeport
ARG KUBEPORT_REF=main
RUN bench get-app kubeport "${KUBEPORT_REPO}" --branch "${KUBEPORT_REF}" --resolve-deps

# Sanity: kubeport is on the bench, helm is on PATH.
RUN test -d apps/kubeport \
 && /usr/local/bin/helm version --short \
 && bench --help >/dev/null

USER root
COPY images/kubeport/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY images/kubeport/seed_default_cluster.py /home/frappe/seed_default_cluster.py
RUN chmod 0755 /usr/local/bin/entrypoint.sh \
 && chown frappe:frappe /home/frappe/seed_default_cluster.py
USER frappe

EXPOSE 8000

# common_site_config.json is rewritten by entrypoint on first start so the bench
# uses the docker-compose mariadb / redis services rather than 127.0.0.1.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bench", "start"]
