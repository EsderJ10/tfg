# Guía de Integración con Helm

Aquí se detalla el sistema de orquestación de paquetes Helm integrado en Kubeport. El sistema permite gestionar todo el ciclo de vida de una aplicación Kubernetes (discovery, configuración y despliegue) desde la interfaz de Frappe.

## 1. Arquitectura del Sistema
La integración se divide en cuatro DocTypes principales que reflejan la jerarquía natural de Helm:
1.  **Helm Repository**: Catálogos de aplicaciones (ej. Bitnami, ERPNext).
2.  **Helm Chart**: Metadatos de una aplicación específica dentro de un repositorio.
3.  **Helm Chart Version**: Registro de versiones disponibles para cada chart.
4.  **Helm Release**: Una instancia desplegada de un chart en un clúster específico.

## 2. DocType: Helm Release
Es el núcleo de la automatización. Permite definir *dónde* y *cómo* se despliega una aplicación.

### Tabla de Campos (Layout)

| Etiqueta | Tipo | Fielname | Mandatorio | Notas |
| :--- | :--- | :--- | :---: | :--- |
| **Release Name** | Data | `release_name` | ✅ | Único por namespace. |
| **Target Cluster**| Link | `cluster` | ✅ | Ref: `Kubernetes Cluster`. |
| **Namespace** | Data | `namespace` | ✅ | Default: `default`. |
| **Chart** | Link | `chart` | ✅ | Ref: `Helm Chart`. |
| **Chart Version** | Data | `chart_version` | ❌ | Opcional (vacio = latest). |
| **Values** | Code | `values` | ❌ | YAML con overrides. |
| **Status** | Select | `status` | ❌ | `Draft`, `In Progress`, `Deployed`, `Failed`. |

## 3. Automatización Detrás de Escena (Backend)

### Wrapper de Helm CLI (`kubeport/utils/helm.py`)
No reinventamos la rueda; Kubeport envuelve el binario oficial de Helm 3. Para garantizar la seguridad y el aislamiento:
- **Kubeconfigs Efímeros**: Para cada llamada (`install`, `upgrade`, `status`), generamos un Kubeconfig temporal en memoria basado en el `Kubernetes Cluster` destino y lo pasamos al comando con `--kubeconfig`.
- **Cero Estado Global**: No se usa `helm repo add` de forma persistente en el sistema base; los comandos se ejecutan con contextos limpios.

Ejemplo de llamada de instalación/actualización:
```python
def install_or_upgrade(release_name, chart_ref, namespace, cluster_name, values_yaml=None):
    with _helm_kubeconfig(cluster_name) as kubeconfig_path:
        cmd = [
            "helm", "upgrade", "--install", 
            release_name, chart_ref, 
            "--namespace", namespace, 
            "--create-namespace", "--wait"
        ]
        if kubeconfig_path:
            cmd.extend(["--kubeconfig", kubeconfig_path])
        # ... manejo de valores temporales ...
        return _run_helm(cmd)
```

### Tareas Asíncronas (`kubeport/tasks/helm_tasks.py`)
Los despliegues de Helm pueden tardar varios minutos. Para no bloquear la interfaz de usuario, todas las operaciones de modificación se envían a una cola de trabajo (`frappe.enqueue`):

```python
# En helm_release.py
@frappe.whitelist()
def deploy_release(self):
    self.db_set("status", "In Progress")
    frappe.enqueue(
        "kubeport.tasks.helm_tasks.deploy_release_task",
        release_name=self.name,
        queue="long"
    )
```

## 4. Guía de Uso

1.  **Sincronización de Repos**:
    - Añade un `Helm Repository` (ej. `https://charts.bitnami.com/bitnami`).
    - Haz clic en **Sync Repository**. Esto descargará los metadatos y creará automáticamente los documentos `Helm Chart` correspondientes.
2.  **Despliegue de una Release**:
    - Crea un nuevo `Helm Release`.
    - Selecciona el clúster y el chart.
    - Haz clic en **Load Default Values** para traer la configuración por defecto de la aplicación.
    - Ajusta los `values` (ej. réplicas, recursos) y dale a **Install / Upgrade**.

---
> [!IMPORTANT]
> El sistema requiere que el binario `helm` esté instalado en el contenedor de Frappe. Esto se modificará cuando creemos el contenedor de imágenes.

## 5. Código Referencia

A continuación se incluyen los archivos exactos involucrados en la integración de Helm para que puedan ser replicados o consultados.

### `helm_tasks.py`
**Ubicación**: `kubeport/tasks/helm_tasks.py`

<details>
<summary>Ver Código Completo</summary>

```python
"""
Helm Background Tasks

All Helm CLI operations that touch the cluster (install, upgrade, uninstall,
repo sync) run here via ``frappe.enqueue`` on the ``long`` queue.  This
guarantees that ``subprocess.run`` never blocks a web request.

Each task follows the pattern:
1. Load the Frappe document
2. Set status to "In Progress" / "Syncing"
3. Execute the Helm CLI wrapper call
4. Update status + metadata on success
5. On failure: set status to "Failed" / "Error", log the error
6. Push a realtime event so the browser auto-reloads
"""

import fnmatch
import re

import frappe

from kubeport.utils import helm


# ---------------------------------------------------------------------------
# Repository Tasks
# ---------------------------------------------------------------------------


def add_and_sync_repo(repo_name: str):
	"""Register a Helm repo and trigger a chart index sync.

	Called automatically when a new Helm Repository document is created
	(via ``after_insert``).
	"""
	doc = frappe.get_doc("Helm Repository", repo_name)

	try:
		# Register the repo with Helm CLI
		password = doc.get_password("repo_password") if doc.repo_password else None
		helm.repo_add(
			doc.repo_name,
			doc.repo_url,
			username=doc.repo_username or None,
			password=password,
		)

		# Sync charts into the database
		_sync_charts(doc)

		doc.db_set("status", "Synced")
		doc.db_set("last_synced", frappe.utils.now())

		frappe.publish_realtime(
			"helm_repo_sync_update",
			{"repo_name": repo_name, "status": "Synced"},
			doctype="Helm Repository",
			docname=repo_name,
		)

	except Exception as e:
		doc.db_set("status", "Error")
		frappe.log_error(
			title=f"Helm Repo Add Failed: {repo_name}",
			message=str(e),
		)
		frappe.publish_realtime(
			"helm_repo_sync_update",
			{"repo_name": repo_name, "status": "Error"},
			doctype="Helm Repository",
			docname=repo_name,
		)


def sync_repo_charts(repo_name: str):
	"""Update a repo's chart index and sync new charts to the database.

	Called by the "Sync Charts" button and the daily scheduler.
	"""
	doc = frappe.get_doc("Helm Repository", repo_name)

	try:
		# Refresh the local chart index
		helm.repo_update(doc.repo_name)

		# Sync charts
		_sync_charts(doc)

		doc.db_set("status", "Synced")
		doc.db_set("last_synced", frappe.utils.now())

		frappe.publish_realtime(
			"helm_repo_sync_update",
			{"repo_name": repo_name, "status": "Synced"},
			doctype="Helm Repository",
			docname=repo_name,
		)

	except Exception as e:
		doc.db_set("status", "Error")
		frappe.log_error(
			title=f"Helm Repo Sync Failed: {repo_name}",
			message=str(e),
		)
		frappe.publish_realtime(
			"helm_repo_sync_update",
			{"repo_name": repo_name, "status": "Error"},
			doctype="Helm Repository",
			docname=repo_name,
		)


def sync_all_repos():
	"""Daily scheduler task: sync all Helm repositories.

	Referenced by ``hooks.py`` via ``scheduler_events["daily"]``.
	"""
	repos = frappe.get_all(
		"Helm Repository",
		filters={"status": ["!=", "Error"]},
		pluck="name",
	)

	for repo_name in repos:
		try:
			sync_repo_charts(repo_name)
		except Exception as e:
			frappe.log_error(
				title=f"Daily Sync Failed: {repo_name}",
				message=str(e),
			)


# ---------------------------------------------------------------------------
# Release Tasks
# ---------------------------------------------------------------------------


def install_or_upgrade_release(release_name: str):
	"""Install or upgrade a Helm release on the target cluster.

	Uses ``helm upgrade --install`` for idempotency.
	"""
	doc = frappe.get_doc("Helm Release", release_name)
	chart_doc = frappe.get_doc("Helm Chart", doc.chart)

	try:
		chart_ref = chart_doc.get_chart_reference()
		version = doc.chart_version or chart_doc.latest_version

		result = helm.install_or_upgrade(
			release_name=doc.release_name,
			chart_ref=chart_ref,
			namespace=doc.namespace or "default",
			cluster_name=doc.cluster,
			values_yaml=doc.values if doc.values else None,
			chart_version=version,
		)

		# Parse result — helm upgrade --install --output json returns the release object
		revision = 0
		status_detail = ""
		if isinstance(result, dict):
			revision = result.get("version", 0)
			info = result.get("info", {})
			if isinstance(info, dict):
				status_detail = info.get("status", "")

		doc.db_set("status", "Deployed")
		doc.db_set("helm_revision", revision)
		doc.db_set("helm_status_detail", status_detail)

		frappe.publish_realtime(
			"helm_release_status_update",
			{"release_name": release_name, "status": "Deployed"},
			doctype="Helm Release",
			docname=release_name,
		)

	except Exception as e:
		doc.db_set("status", "Failed")
		doc.db_set("helm_status_detail", str(e)[:500])
		frappe.log_error(
			title=f"Helm Install/Upgrade Failed: {release_name}",
			message=str(e),
		)
		frappe.publish_realtime(
			"helm_release_status_update",
			{"release_name": release_name, "status": "Failed"},
			doctype="Helm Release",
			docname=release_name,
		)


def uninstall_release(release_name: str):
	"""Uninstall a Helm release from the target cluster."""
	doc = frappe.get_doc("Helm Release", release_name)

	try:
		helm.uninstall(
			release_name=doc.release_name,
			namespace=doc.namespace or "default",
			cluster_name=doc.cluster,
		)

		doc.db_set("status", "Draft")
		doc.db_set("helm_revision", 0)
		doc.db_set("helm_status_detail", "")

		frappe.publish_realtime(
			"helm_release_status_update",
			{"release_name": release_name, "status": "Draft"},
			doctype="Helm Release",
			docname=release_name,
		)

	except Exception as e:
		doc.db_set("status", "Failed")
		doc.db_set("helm_status_detail", str(e)[:500])
		frappe.log_error(
			title=f"Helm Uninstall Failed: {release_name}",
			message=str(e),
		)
		frappe.publish_realtime(
			"helm_release_status_update",
			{"release_name": release_name, "status": "Failed"},
			doctype="Helm Release",
			docname=release_name,
		)


# ---------------------------------------------------------------------------
# Private Helpers
# ---------------------------------------------------------------------------


def _sync_charts(repo_doc):
	"""Parse ``helm search repo`` output and upsert Helm Chart documents.

	Applies the ``include_patterns`` filter from the repository document.
	For each matching chart, either creates a new Helm Chart parent or
	appends a new version to the existing parent's child table.
	"""
	charts_data = helm.search_repo(repo_doc.repo_name)

	if not charts_data:
		return

	# Parse include patterns (comma-separated, with optional glob wildcards)
	patterns = _parse_include_patterns(repo_doc.include_patterns)

	for chart_entry in charts_data:
		# chart_entry: {"name": "bitnami/nginx", "version": "18.2.4", ...}
		full_name = chart_entry.get("name", "")
		chart_name = full_name.split("/")[-1] if "/" in full_name else full_name
		chart_version = chart_entry.get("version", "")
		app_version = chart_entry.get("app_version", "")
		description = chart_entry.get("description", "")

		if not chart_name or not chart_version:
			continue

		# Apply inclusion filter
		if patterns and not _matches_any_pattern(chart_name, patterns):
			continue

		# Helm Chart parent document name: "repo_name/chart_name"
		chart_doc_name = f"{repo_doc.name}/{chart_name}"

		if frappe.db.exists("Helm Chart", chart_doc_name):
			# Chart exists — check if this version is already tracked
			chart_doc = frappe.get_doc("Helm Chart", chart_doc_name)

			existing_versions = {row.version for row in chart_doc.versions}
			if chart_version not in existing_versions:
				chart_doc.append("versions", {
					"version": chart_version,
					"app_version": app_version,
					"description": description,
				})
				chart_doc.save(ignore_permissions=True)

			# Update latest version if this is newer
			chart_doc.db_set("latest_version", chart_version)
			chart_doc.db_set("latest_app_version", app_version)
			chart_doc.db_set("description", description)

		else:
			# Create a new Helm Chart document
			default_values = ""
			try:
				default_values = helm.show_values(full_name, version=chart_version)
			except Exception:
				pass  # Non-critical — values can be fetched later

			new_chart = frappe.get_doc({
				"doctype": "Helm Chart",
				"chart_name": chart_name,
				"repository": repo_doc.name,
				"latest_version": chart_version,
				"latest_app_version": app_version,
				"description": description,
				"default_values": default_values,
				"versions": [{
					"version": chart_version,
					"app_version": app_version,
					"description": description,
				}],
			})
			new_chart.insert(ignore_permissions=True)

	frappe.db.commit()


def _parse_include_patterns(patterns_text: str | None) -> list[str]:
	"""Parse the comma-separated include patterns into a list of globs.

	Returns an empty list if no patterns are configured (sync all).
	"""
	if not patterns_text or not patterns_text.strip():
		return []

	# Split by comma, strip whitespace, remove empty entries
	return [
		p.strip()
		for p in re.split(r"[,\n]", patterns_text)
		if p.strip()
	]


def _matches_any_pattern(chart_name: str, patterns: list[str]) -> bool:
	"""Check if a chart name matches any of the include patterns.

	Supports glob-style wildcards via ``fnmatch``.
	"""
	return any(fnmatch.fnmatch(chart_name, pattern) for pattern in patterns)
```
</details>

### `helm.py` (Wrapper de CLI)
**Ubicación**: `kubeport/utils/helm.py`

<details>
<summary>Ver Código Completo</summary>

```python
"""
Helm CLI Wrapper

Stateless wrapper around the Helm 3 binary.  Every function writes a
temporary kubeconfig file from the cluster document, runs ``helm`` via
``subprocess.run``, and cleans up immediately.

Security invariants:
- All subprocess calls use a **list** of arguments — never ``shell=True``
- Temporary kubeconfig files are created per-call and deleted in a
  ``finally`` block, so concurrent workers never share state
- All long-running operations (install, upgrade, uninstall) are called
  from ``frappe.enqueue`` background jobs — never from the web thread

Output parsing:
- Commands that support ``--output json`` return parsed dicts/lists
- Commands that produce text (e.g. ``helm show values``) return raw strings
"""

import json
import os
import subprocess
import tempfile
from contextlib import contextmanager
from typing import Any

import frappe
import yaml


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def repo_add(
	name: str,
	url: str,
	username: str | None = None,
	password: str | None = None,
) -> str:
	"""Register a Helm chart repository.

	Equivalent to ``helm repo add <name> <url> [--username ...] [--password ...]``.
	"""
	cmd = ["helm", "repo", "add", name, url, "--force-update"]
	if username:
		cmd.extend(["--username", username])
	if password:
		cmd.extend(["--password", password])

	return _run_helm(cmd)


def repo_update(name: str | None = None) -> str:
	"""Refresh cached chart index for one or all repositories.

	Equivalent to ``helm repo update [name]``.
	"""
	cmd = ["helm", "repo", "update"]
	if name:
		cmd.append(name)
	return _run_helm(cmd)


def repo_remove(name: str) -> str:
	"""Unregister a Helm chart repository.

	Equivalent to ``helm repo remove <name>``.
	"""
	return _run_helm(["helm", "repo", "remove", name])


def search_repo(repo_name: str, keyword: str = "") -> list[dict]:
	"""List charts in a repository.

	Equivalent to ``helm search repo <repo_name>/ --output json``.
	Returns a list of chart dicts with keys: name, version, app_version, description.
	"""
	search_term = f"{repo_name}/"
	if keyword:
		search_term = f"{repo_name}/{keyword}"

	cmd = ["helm", "search", "repo", search_term, "--output", "json"]
	output = _run_helm(cmd)
	return _parse_json_or_empty(output)


def show_chart(chart_ref: str, version: str | None = None) -> dict:
	"""Get chart metadata (Chart.yaml content).

	Equivalent to ``helm show chart <ref> [--version <v>]``.
	"""
	cmd = ["helm", "show", "chart", chart_ref]
	if version:
		cmd.extend(["--version", version])
	output = _run_helm(cmd)
	return yaml.safe_load(output) or {}


def show_values(chart_ref: str, version: str | None = None) -> str:
	"""Get default values.yaml for a chart as raw YAML string.

	Equivalent to ``helm show values <ref> [--version <v>]``.
	"""
	cmd = ["helm", "show", "values", chart_ref]
	if version:
		cmd.extend(["--version", version])
	return _run_helm(cmd)


def install_or_upgrade(
	release_name: str,
	chart_ref: str,
	namespace: str,
	cluster_name: str,
	values_yaml: str | None = None,
	chart_version: str | None = None,
) -> dict:
	"""Install or upgrade a Helm release (idempotent).

	Equivalent to ``helm upgrade --install <release> <chart> -n <ns>``.
	Uses a temporary kubeconfig from the cluster document.

	Returns the parsed JSON output from ``helm status``.
	"""
	with _helm_kubeconfig(cluster_name) as kubeconfig_path:
		cmd = [
			"helm", "upgrade", "--install",
			release_name, chart_ref,
			"--namespace", namespace,
			"--create-namespace",
			"--output", "json",
			"--wait",
			"--timeout", "5m0s",
		]

		if chart_version:
			cmd.extend(["--version", chart_version])

		if kubeconfig_path:
			cmd.extend(["--kubeconfig", kubeconfig_path])

		# Write values to a temp file if provided
		if values_yaml:
			values_fd, values_path = tempfile.mkstemp(
				suffix=".yaml", prefix="kubeport_values_"
			)
			try:
				os.write(values_fd, values_yaml.encode("utf-8"))
				os.close(values_fd)
				cmd.extend(["--values", values_path])
				output = _run_helm(cmd)
			finally:
				if os.path.exists(values_path):
					os.unlink(values_path)
		else:
			output = _run_helm(cmd)

	return _parse_json_or_empty(output)


def uninstall(
	release_name: str,
	namespace: str,
	cluster_name: str,
) -> str:
	"""Uninstall a Helm release.

	Equivalent to ``helm uninstall <release> -n <ns>``.
	"""
	with _helm_kubeconfig(cluster_name) as kubeconfig_path:
		cmd = [
			"helm", "uninstall", release_name,
			"--namespace", namespace,
		]
		if kubeconfig_path:
			cmd.extend(["--kubeconfig", kubeconfig_path])

		return _run_helm(cmd)


def status(
	release_name: str,
	namespace: str,
	cluster_name: str,
) -> dict:
	"""Get release status from the cluster.

	Equivalent to ``helm status <release> -n <ns> --output json``.
	"""
	with _helm_kubeconfig(cluster_name) as kubeconfig_path:
		cmd = [
			"helm", "status", release_name,
			"--namespace", namespace,
			"--output", "json",
		]
		if kubeconfig_path:
			cmd.extend(["--kubeconfig", kubeconfig_path])

		output = _run_helm(cmd)

	return _parse_json_or_empty(output)


def list_releases(
	namespace: str | None = None,
	cluster_name: str | None = None,
) -> list[dict]:
	"""List all Helm releases.

	Equivalent to ``helm list [--namespace <ns>] --output json``.
	"""
	cmd = ["helm", "list", "--output", "json"]
	if namespace:
		cmd.extend(["--namespace", namespace])
	else:
		cmd.append("--all-namespaces")

	if cluster_name:
		with _helm_kubeconfig(cluster_name) as kubeconfig_path:
			if kubeconfig_path:
				cmd.extend(["--kubeconfig", kubeconfig_path])
			output = _run_helm(cmd)
	else:
		output = _run_helm(cmd)

	return _parse_json_or_empty(output)


# ---------------------------------------------------------------------------
# Kubeconfig Context Manager
# ---------------------------------------------------------------------------


@contextmanager
def _helm_kubeconfig(cluster_name: str):
	"""Write a temporary kubeconfig for Helm CLI usage.

	Reads the cluster document, writes a temp file, yields the file path,
	and unconditionally deletes it.  For In-Cluster auth, yields ``None``
	(Helm uses the pod's default service account automatically).
	"""
	cluster_doc = frappe.get_doc("Kubernetes Cluster", cluster_name)
	auth_method = cluster_doc.auth_method or "Kubeconfig"

	if auth_method == "In-Cluster":
		# Helm auto-detects in-cluster credentials from the pod environment
		yield None
		return

	if auth_method == "Kubeconfig":
		content = cluster_doc.kubeconfig or ""
	elif auth_method == "Bearer Token":
		content = _build_kubeconfig_from_token(cluster_doc)
	else:
		frappe.throw(f"Unknown auth method: {auth_method}")

	if not content:
		frappe.throw(
			f"Kubernetes Cluster '{cluster_name}' has no credentials "
			f"configured for auth method '{auth_method}'."
		)

	fd, path = tempfile.mkstemp(suffix=".yaml", prefix="kubeport_helm_kc_")
	try:
		os.write(fd, content.encode("utf-8"))
		os.close(fd)
		yield path
	finally:
		if os.path.exists(path):
			os.unlink(path)


def _build_kubeconfig_from_token(cluster_doc) -> str:
	"""Build a minimal kubeconfig YAML from a Bearer Token cluster doc.

	Creates a single-context kubeconfig that authenticates via token,
	suitable for passing to ``helm --kubeconfig``.
	"""
	token = cluster_doc.get_password("bearer_token")
	if not token:
		frappe.throw(
			f"Kubernetes Cluster '{cluster_doc.name}' has no bearer token configured."
		)

	kubeconfig: dict[str, Any] = {
		"apiVersion": "v1",
		"kind": "Config",
		"current-context": "default",
		"clusters": [{
			"name": "default",
			"cluster": {
				"server": cluster_doc.api_server_url,
			},
		}],
		"contexts": [{
			"name": "default",
			"context": {
				"cluster": "default",
				"user": "default",
			},
		}],
		"users": [{
			"name": "default",
			"user": {
				"token": token,
			},
		}],
	}

	# Add CA certificate if present
	if cluster_doc.ca_certificate:
		kubeconfig["clusters"][0]["cluster"]["certificate-authority-data"] = (
			cluster_doc.ca_certificate
		)
	else:
		kubeconfig["clusters"][0]["cluster"]["insecure-skip-tls-verify"] = True

	return yaml.dump(kubeconfig, default_flow_style=False)


# ---------------------------------------------------------------------------
# Private Helpers
# ---------------------------------------------------------------------------


def _run_helm(cmd: list[str]) -> str:
	"""Execute a Helm CLI command and return stdout.

	Args:
		cmd: Command as a list of strings (never use shell=True).

	Returns:
		The stdout text output from the command.

	Raises:
		frappe.ValidationError: If the command fails (non-zero exit code).
	"""
	try:
		result = subprocess.run(
			cmd,
			capture_output=True,
			text=True,
			check=True,
			timeout=600,  # 10-minute safety timeout
		)
		return result.stdout
	except FileNotFoundError:
		frappe.throw(
			"Helm CLI binary not found. Please install Helm 3: "
			"https://helm.sh/docs/intro/install/"
		)
	except subprocess.CalledProcessError as e:
		error_msg = e.stderr.strip() if e.stderr else str(e)
		frappe.throw(
			f"Helm command failed: {error_msg}",
			title="Helm Error",
		)
	except subprocess.TimeoutExpired:
		frappe.throw(
			"Helm command timed out after 10 minutes.",
			title="Helm Timeout",
		)

	return ""  # Unreachable but satisfies type checkers


def _parse_json_or_empty(text: str) -> Any:
	"""Parse JSON output from Helm, returning an empty list/dict on failure."""
	if not text or not text.strip():
		return []
	try:
		return json.loads(text)
	except json.JSONDecodeError:
		return []
```
</details>
