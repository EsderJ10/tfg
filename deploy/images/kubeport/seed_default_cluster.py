#!/usr/bin/env python3
"""Idempotent seeder for the eval-stack Kubernetes Cluster row.

Invoked once per first container start by entrypoint.sh, using the bench's
Python interpreter so frappe is importable:

    cd /home/frappe/kubeport-bench
    env/bin/python /home/frappe/seed_default_cluster.py \
        --site kubeport.localhost \
        --cluster-name eval-k3s \
        --kubeconfig /shared/k3s/kubeconfig.yaml

The script:
  1. Reads the k3s kubeconfig from the shared volume.
  2. Rewrites the API server URL from the loopback default to the
     compose service hostname (k3s:6443) so the bench can reach it.
  3. Inserts a Kubernetes Cluster row with auth_method=Kubeconfig and
     skip_tls_verify=1 (k3s ships a self-signed cert that does not
     match the compose service hostname).
  4. No-ops when the row already exists (refreshes kubeconfig content).

Failures are non-fatal — entrypoint.sh logs and continues so the bench
still serves; the operator can connect a cluster manually from the UI.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

import yaml


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", required=True, help="Frappe site name (e.g. kubeport.localhost)")
    parser.add_argument(
        "--cluster-name",
        default="eval-k3s",
        help="Docname for the Kubernetes Cluster row",
    )
    parser.add_argument(
        "--kubeconfig",
        default="/shared/k3s/kubeconfig.yaml",
        help="Path to the k3s-written kubeconfig in the shared volume",
    )
    args = parser.parse_args(argv)

    src = Path(args.kubeconfig)
    if not src.is_file():
        print(f"[seed] kubeconfig not found at {src}; skipping seed", file=sys.stderr)
        return 0  # non-fatal

    raw = src.read_text(encoding="utf-8")
    rewritten = _rewrite_loopback(raw)
    context = _first_context(rewritten)

    # Frappe must be initialised against the bench's site context.  The bench
    # working directory provides the sites/common_site_config.json path.
    import frappe

    frappe.init(site=args.site)
    frappe.connect()
    try:
        if frappe.db.exists("Kubernetes Cluster", args.cluster_name):
            print(f"[seed] Kubernetes Cluster '{args.cluster_name}' already exists; refreshing kubeconfig")
            doc = frappe.get_doc("Kubernetes Cluster", args.cluster_name)
            doc.kubeconfig = rewritten
            doc.kubeconfig_context = context
            doc.skip_tls_verify = 1
            doc.save(ignore_permissions=True)
        else:
            print(f"[seed] inserting Kubernetes Cluster '{args.cluster_name}'")
            doc = frappe.get_doc(
                {
                    "doctype": "Kubernetes Cluster",
                    "cluster_name": args.cluster_name,
                    "auth_method": "Kubeconfig",
                    "kubeconfig": rewritten,
                    "kubeconfig_context": context,
                    "skip_tls_verify": 1,
                }
            )
            doc.insert(ignore_permissions=True)
        frappe.db.commit()
        print(
            f"[seed] done — open /app/kubernetes-cluster/{args.cluster_name} "
            "and click Test Connection"
        )
        return 0
    finally:
        frappe.destroy()


def _rewrite_loopback(kubeconfig_yaml: str) -> str:
    """Replace 127.0.0.1 / localhost / 0.0.0.0 in cluster.server with the compose hostname."""
    parsed: Any = yaml.safe_load(kubeconfig_yaml)
    if not isinstance(parsed, dict):
        return kubeconfig_yaml
    clusters = parsed.get("clusters") or []
    for cluster in clusters:
        details = cluster.get("cluster") if isinstance(cluster, dict) else None
        if not isinstance(details, dict):
            continue
        server = details.get("server")
        if not isinstance(server, str):
            continue
        for needle in ("127.0.0.1", "localhost", "0.0.0.0"):
            if needle in server:
                details["server"] = server.replace(needle, "k3s")
                break
    return yaml.safe_dump(parsed, default_flow_style=False, sort_keys=False)


def _first_context(kubeconfig_yaml: str) -> str:
    parsed: Any = yaml.safe_load(kubeconfig_yaml)
    if not isinstance(parsed, dict):
        return ""
    current = parsed.get("current-context")
    if isinstance(current, str) and current:
        return current
    contexts = parsed.get("contexts") or []
    if contexts and isinstance(contexts[0], dict):
        name = contexts[0].get("name")
        if isinstance(name, str):
            return name
    return ""


if __name__ == "__main__":
    sys.exit(main())
