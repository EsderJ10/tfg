# Clúster Kubernetes Agnóstico (Multi-Auth)

Aquí cubrimos la refactorización del DocType **Kubernetes Cluster** para permitir conexiones agnósticas al proveedor y entorno, eliminando la dependencia exclusiva de archivos Kubeconfig persistentes.

## 1. Motivación del Cambio
Anteriormente, la aplicación solo podía conectarse a clústeres mediante un archivo `kubeconfig` pegado en un campo de texto. Esto limitaba la integración en dos escenarios críticos:
1.  **Despliegues In-Cluster**: Cuando Kubeport se ejecuta dentro de un pod de Kubernetes, debe usar su propia `ServiceAccount` sin necesidad de archivos externos.
2.  **Seguridad por Token**: Muchos clústeres administrados (EKS, GKE, AKS) prefieren el uso de tokens de rotación o cuentas de servicio específicas, que son más seguras y fáciles de gestionar que un Kubeconfig completo.

## 2. Configuración del DocType: Kubernetes Cluster

Se han añadido campos condicionales que se activan según el **Auth Method** seleccionado.

### Tabla de Campos (Layout Actualizado)

| Etiqueta | Tipo | Fielname | Mandatorio | Dependencia / Notas |
| :--- | :--- | :--- | :---: | :--- |
| **Auth Method** | Select | `auth_method` | ✅ | `Kubeconfig`, `Bearer Token`, `In-Cluster`. |
| **Kubeconfig** | Code | `kubeconfig` | ❌ | Solo si `auth_method == 'Kubeconfig'`. |
| **API Server URL**| Data | `api_server_url`| ❌ | Solo si `auth_method == 'Bearer Token'`. |
| **Bearer Token** | Password | `bearer_token` | ❌ | Solo si `auth_method == 'Bearer Token'`. Encriptado en DB. |
| **CA Certificate**| Code | `ca_certificate`| ❌ | Opcional para `Bearer Token`. Formato PEM. |
| **Skip TLS Verify**| Check | `skip_tls_verify`| ❌ | Solo para desarrollo local. |

## 3. Lógica de Conexión Centralizada (Client Factory)

Para evitar la duplicación de código y errores de estado global en el cliente de Python, se ha implementado una fábrica de clientes en `kubeport/utils/k8s_client.py`.

### El método `get_k8s_api_client`
Este método devuelve una instancia de `kubernetes.client.ApiClient` configurada dinámicamente:

```python
def get_k8s_api_client(cluster_name: str) -> client.ApiClient:
    cluster_doc = frappe.get_doc("Kubernetes Cluster", cluster_name)
    auth_method = cluster_doc.auth_method or "Kubeconfig"

    if auth_method == "Kubeconfig":
        return _client_from_kubeconfig(cluster_doc)
    elif auth_method == "Bearer Token":
        return _client_from_bearer_token(cluster_doc)
    elif auth_method == "In-Cluster":
        return _client_from_incluster()
```

### Gestión Segura de CA (Certificados)
El cliente de Kubernetes requiere una *ruta de archivo* para el certificado CA. Dado que almacenamos el certificado en la base de datos como texto (PEM), lo escribimos en un archivo temporal seguro que se elimina automáticamente al finalizar el proceso worker de Frappe mediante `atexit`:

```python
def _write_ca_tempfile(ca_pem: str) -> str:
    ca_fd, ca_path = tempfile.mkstemp(suffix=".pem", prefix="kubeport_ca_")
    os.write(ca_fd, ca_pem.encode("utf-8"))
    os.close(ca_fd)
    # Programar eliminación automática para evitar fugas de archivos
    atexit.register(lambda p=ca_path: os.unlink(p) if os.path.exists(p) else None)
    return ca_path
```

## 4. Guía de Uso

1.  **Para Desarrollo Local (K3d/Kind)**:
    - Usar método `Kubeconfig`.
    - Activar `Skip TLS Verification` si el certificado no incluye la IP de la red de Docker.
2.  **Para Producción (External)**:
    - Se recomienda `Bearer Token`. Crearemos seguramente una `ServiceAccount` en el clúster con permisos de `cluster-admin` (o específicos), obtendremos su token y lo pegaremos en el campo correspondiente.
3.  **Para Producción (Self-Hosted)**:
    - Si Kubeport corre dentro del clúster que gestiona, simplemente selecciona `In-Cluster`. No requiere configuración adicional.

---
> [!TIP]
> Al usar `config.new_client_from_config_dict` o configurar instancias de `Configuration` manualmente, garantizamos que las peticiones concurrentes a diferentes clústeres no interfieran entre sí (Thread Safety).

## 5. Código Referencia

A continuación se incluyen los archivos exactos para poder replicar el comportamiento agnóstico en el entorno del clúster u otros entornos.

### `kubernetes_cluster.py`
**Ubicación**: `kubeport/kubeport/doctype/kubernetes_cluster/kubernetes_cluster.py`

<details>
<summary>Ver Código Completo</summary>

```python
import frappe
from frappe.model.document import Document
from kubernetes import client

from kubeport.utils.k8s_client import get_k8s_api_client


class KubernetesCluster(Document):
	# begin: auto-generated types
	# This code is auto-generated. Do not modify anything in this block.

	from typing import TYPE_CHECKING

	if TYPE_CHECKING:
		from frappe.types import DF

		api_server_url: DF.Data | None
		auth_method: DF.Literal["Kubeconfig", "Bearer Token", "In-Cluster"]
		bearer_token: DF.Password | None
		ca_certificate: DF.Code | None
		cluster_name: DF.Data
		kubeconfig: DF.Code | None
		kubeconfig_context: DF.Data | None
		skip_tls_verify: DF.Check
		status: DF.Literal["Pending", "Connected", "Error"]
	# end: auto-generated types

	def validate(self):
		"""Validate that required fields for the selected auth method are present."""
		if self.auth_method == "Kubeconfig":
			if not self.kubeconfig:
				frappe.throw("A kubeconfig is required when using the Kubeconfig auth method.")
			self._validate_kubeconfig_syntax()

		elif self.auth_method == "Bearer Token":
			if not self.api_server_url:
				frappe.throw("An API Server URL is required when using Bearer Token auth.")
			if not self.bearer_token:
				frappe.throw("A Bearer Token is required when using Bearer Token auth.")
			if not self.api_server_url.startswith("https://"):
				frappe.throw("API Server URL must start with https://")

		# In-Cluster requires no user-provided fields — the service account
		# is auto-detected from the pod environment at connection time.

	def _validate_kubeconfig_syntax(self):
		"""Check that the kubeconfig field contains valid YAML."""
		import yaml

		try:
			parsed = yaml.safe_load(self.kubeconfig)
			if not isinstance(parsed, dict):
				frappe.throw("Kubeconfig must be a YAML mapping, not a scalar or list.")
		except yaml.YAMLError as e:
			frappe.throw(f"Invalid kubeconfig YAML: {e}")

	@frappe.whitelist()
	def test_connection(self):
		"""Test connectivity to the cluster using the configured auth method."""
		try:
			api_client = get_k8s_api_client(self.name)
			v1 = client.CoreV1Api(api_client=api_client)
			nodes = v1.list_node()

			self.db_set("status", "Connected")
			frappe.msgprint(
				f"Successfully connected. The cluster responded and has {len(nodes.items)} node(s).",
				alert=True,
				indicator="green",
			)

		except Exception as e:
			self.db_set("status", "Error")
			frappe.throw(f"Failed to connect: {str(e)}")
```
</details>

### `k8s_client.py`
**Ubicación**: `kubeport/utils/k8s_client.py`

<details>
<summary>Ver Código Completo</summary>

```python
"""
Kubernetes API Client Factory

Creates a configured ``kubernetes.client.ApiClient`` instance from a
Kubernetes Cluster DocType record.  Supports multiple authentication methods:

- **Kubeconfig** — loads a user-provided kubeconfig YAML in-memory.
- **Bearer Token** — connects to a remote API server using a service-account
  token and optional CA certificate.
- **In-Cluster** — auto-detects credentials from the pod environment when
  Kubeport is deployed inside Kubernetes.
"""

import atexit
import os
import tempfile

import frappe
import urllib3
import yaml
from kubernetes import client, config


def get_k8s_api_client(cluster_name: str) -> client.ApiClient:
	"""Create a Kubernetes API client from a Kubernetes Cluster DocType record.

	The auth method is determined by the ``auth_method`` field on the cluster
	document.  Each method produces a fully configured ApiClient that can be
	used to instantiate any K8s API group (CoreV1Api, AppsV1Api, etc.).

	Args:
		cluster_name: The name (primary key) of the Kubernetes Cluster DocType.

	Returns:
		A configured kubernetes.client.ApiClient instance.

	Raises:
		frappe.ValidationError: If the cluster record is missing required fields.
	"""
	cluster_doc = frappe.get_doc("Kubernetes Cluster", cluster_name)

	auth_method = cluster_doc.auth_method or "Kubeconfig"

	if auth_method == "Kubeconfig":
		return _client_from_kubeconfig(cluster_doc)
	elif auth_method == "Bearer Token":
		return _client_from_bearer_token(cluster_doc)
	elif auth_method == "In-Cluster":
		return _client_from_incluster()
	else:
		frappe.throw(f"Unknown auth method: {auth_method}")


def _client_from_kubeconfig(cluster_doc) -> client.ApiClient:
	"""Build a client from a kubeconfig YAML string (existing behavior)."""
	if not cluster_doc.kubeconfig:
		frappe.throw(f"Kubernetes Cluster '{cluster_doc.name}' has no kubeconfig configured.")

	kubeconfig_dict = yaml.safe_load(cluster_doc.kubeconfig)

	# new_client_from_config_dict returns a scoped ApiClient without mutating
	# global state or writing any files to disk.
	api_client = config.new_client_from_config_dict(config_dict=kubeconfig_dict)

	# Development-only: skip TLS verification for local clusters (K3d, Kind, Minikube)
	# whose self-signed certificates don't include the Docker bridge IP in their SAN.
	if cluster_doc.skip_tls_verify:
		api_client.configuration.verify_ssl = False
		urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

	return api_client


def _client_from_bearer_token(cluster_doc) -> client.ApiClient:
	"""Build a client from an API server URL and service-account token.

	The bearer token is stored as a Frappe Password field, so it's encrypted
	at rest in the database rather than stored as plain text.
	"""
	if not cluster_doc.api_server_url:
		frappe.throw(f"Kubernetes Cluster '{cluster_doc.name}' has no API Server URL configured.")

	token = cluster_doc.get_password("bearer_token")
	if not token:
		frappe.throw(f"Kubernetes Cluster '{cluster_doc.name}' has no bearer token configured.")

	configuration = client.Configuration()
	configuration.host = cluster_doc.api_server_url
	configuration.api_key = {"authorization": f"Bearer {token}"}

	# Use the CA certificate if provided; otherwise skip TLS verification
	if cluster_doc.ca_certificate:
		ca_path = _write_ca_tempfile(cluster_doc.ca_certificate)
		configuration.ssl_ca_cert = ca_path
	else:
		# No CA certificate — skip TLS verification (development only)
		configuration.verify_ssl = False
		urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

	return client.ApiClient(configuration=configuration)


# Well-known paths for in-cluster service account credentials.
_INCLUSTER_TOKEN_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/token"
_INCLUSTER_CA_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
_INCLUSTER_NAMESPACE_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/namespace"


def _client_from_incluster() -> client.ApiClient:
	"""Build a client using in-cluster service account credentials.

	This works when Kubeport is deployed as a pod inside a Kubernetes cluster.
	The service account token and CA certificate are automatically mounted
	by Kubernetes at well-known paths.

	Unlike ``config.load_incluster_config()``, this reads the credentials
	manually and builds a scoped ``Configuration`` instance, so we never
	mutate the global ``kubernetes.client.configuration``.  This is critical
	for multi-user safety — other threads or background jobs that connect
	to *different* clusters must not be affected.
	"""
	if not os.path.isfile(_INCLUSTER_TOKEN_PATH):
		frappe.throw(
			"In-Cluster auth failed: service account token not found at "
			f"{_INCLUSTER_TOKEN_PATH}. Is Kubeport running inside a Kubernetes pod?"
		)

	with open(_INCLUSTER_TOKEN_PATH) as f:
		token = f.read().strip()

	configuration = client.Configuration()
	configuration.host = "https://kubernetes.default.svc"
	configuration.api_key = {"authorization": f"Bearer {token}"}

	if os.path.isfile(_INCLUSTER_CA_PATH):
		configuration.ssl_ca_cert = _INCLUSTER_CA_PATH
	else:
		configuration.verify_ssl = False
		urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

	return client.ApiClient(configuration=configuration)


# ---------------------------------------------------------------------------
# Private Utilities
# ---------------------------------------------------------------------------

def _write_ca_tempfile(ca_pem: str) -> str:
	"""Write a PEM string to a temp file and register cleanup on exit.

	The kubernetes client requires a *file path* for ``ssl_ca_cert``, so we
	write the CA certificate to a temporary file.  An ``atexit`` handler
	ensures the file is removed when the worker process terminates, avoiding
	a slow leak of temp files in long-running Frappe workers.

	Returns:
		The absolute path to the temporary PEM file.
	"""
	ca_fd, ca_path = tempfile.mkstemp(suffix=".pem", prefix="kubeport_ca_")
	try:
		os.write(ca_fd, ca_pem.encode("utf-8"))
	finally:
		os.close(ca_fd)

	# Schedule cleanup so temp files don't accumulate across requests
	atexit.register(lambda p=ca_path: os.unlink(p) if os.path.exists(p) else None)

	return ca_path
```
</details>
