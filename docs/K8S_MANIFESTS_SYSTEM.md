# Sistema de Manifiestos Kubernetes

Aquí se explica el funcionamiento del DocType **Kubernetes Manifest**, diseñado para la gestión directa de recursos de Kubernetes mediante definiciones en formato JSON/YAML.

## 1. Propósito
A diferencia de Helm, que gestiona paquetes complejos con plantillas, el sistema de manifiestos permite el despliegue de recursos atómicos (ej. un `ConfigMap`, un `Secret` específico o un `Pod` de prueba) directamente en el clúster, manteniendo un registro de su estado en Kubeport.

## 2. DocType: Kubernetes Manifest

### Tabla de Campos (Layout)

| Etiqueta | Tipo | Fielname | Mandatorio | Notas |
| :--- | :--- | :--- | :---: | :--- |
| **Manifest Name** | Data | `manifest_name` | ✅ | Identificador único en Kubeport. |
| **Target Cluster**| Link | `cluster` | ✅ | Ref: `Kubernetes Cluster`. |
| **Namespace** | Data | `namespace` | ✅ | Default: `default`. |
| **Content** | Code | `content` | ✅ | Definición del recurso en **JSON**. |
| **Status** | Select | `status` | ❌ | `Draft`, `In Progress`, `Applied`, `Failed`. |

## 3. Flujo de Ejecución Asíncrono

El despliegue de manifiestos no se realiza de forma síncrona para evitar que la interfaz de Frappe se bloquee mientras espera la respuesta de la API de Kubernetes.

### Proceso de Aplicación
1.  **Validación**: Al hacer clic en **Apply**, el backend verifica que el contenido sea un JSON válido.
2.  **Encolado**: Se utiliza `frappe.enqueue` para enviar la tarea a la cola `long`.
3.  **Ejecución (`kubeport/tasks/manifest_tasks.py`)**:
    - Se recupera el cliente de la API para el clúster destino.
    - Se utiliza la utilidad `utils.create_from_dict` (o similar) para aplicar el manifiesto.
    - Se actualiza el campo `status` del documento según el resultado.

```python
# Ejemplo simplificado de la tarea manifest_tasks.py
def apply_manifest_task(manifest_name):
    doc = frappe.get_doc("Kubernetes Manifest", manifest_name)
    api_client = get_k8s_api_client(doc.cluster)
    
    try:
        # Lógica de aplicación de recursos usando el cliente de K8s
        # ...
        doc.db_set("status", "Applied")
    except Exception as e:
        doc.db_set("status", "Failed")
        frappe.log_error("Manifest Apply Error", str(e))
```

## 4. Guía de Uso

1.  **Preparación del Manifiesto**: Asegúrate de que el JSON incluya los campos obligatorios de Kubernetes (`apiVersion`, `kind`, `metadata`, `spec`).
2.  **Despliegue**: Selecciona el clúster y pulsa **Apply**. El estado cambiará a `In Progress` y, tras unos segundos, a `Applied` si todo es correcto.
3.  **Eliminación**: El botón **Delete** permite eliminar el recurso del clúster físico y volver a poner el documento en estado `Draft`.

---
> [!WARNING]
> Actualmente el campo `content` espera **JSON**. Si tienes un manifiesto en YAML, debes convertirlo a JSON antes de pegarlo, o esperar a la actualización que soporte carga directa de YAML.

## 5. Código Referencia

A continuación se incluyen los archivos exactos para que puedan ser replicados o consultados.

### `kubernetes_manifest.py`
**Ubicación**: `kubeport/kubeport/doctype/kubernetes_manifest/kubernetes_manifest.py`

<details>
<summary>Ver Código Completo</summary>

```python
import frappe
from frappe.model.document import Document
import json


class KubernetesManifest(Document):
	# begin: auto-generated types
	# This code is auto-generated. Do not modify anything in this block.

	from typing import TYPE_CHECKING

	if TYPE_CHECKING:
		from frappe.types import DF

		cluster: DF.Link
		content: DF.Code
		manifest_name: DF.Data
		namespace: DF.Data | None
		status: DF.Literal["Draft", "In Progress", "Applied", "Degraded", "Failed"]
	# end: auto-generated types

	@frappe.whitelist()
	def apply_manifest(self):
		if not self.content:
			frappe.throw("The JSON content is empty.")

		# Validate JSON syntax before enqueuing
		try:
			json.loads(self.content)
		except json.JSONDecodeError as e:
			frappe.throw(f"JSON syntax error: {str(e)}")

		if not self.cluster:
			frappe.throw("You must select a target cluster.")

		self.db_set("status", "In Progress")

		frappe.enqueue(
			"kubeport.tasks.apply_manifest_task",
			manifest_name=self.name,
			queue="long",
			enqueue_after_commit=True,
		)

		frappe.msgprint(
			"Manifest application has been queued. Status will update automatically.",
			alert=True,
			indicator="blue",
		)

	@frappe.whitelist()
	def delete_manifest(self):
		if self.status not in ["Applied", "Degraded"]:
			frappe.throw("Only applied or degraded manifests can be deleted.")

		self.db_set("status", "In Progress")

		frappe.enqueue(
			"kubeport.tasks.delete_manifest_task",
			manifest_name=self.name,
			queue="long",
			enqueue_after_commit=True,
		)

		frappe.msgprint(
			"Manifest deletion has been queued. Status will update automatically.",
			alert=True,
			indicator="blue",
		)
```
</details>

### `manifest_tasks.py`
**Ubicación**: `kubeport/tasks/manifest_tasks.py`

<details>
<summary>Ver Código Completo</summary>

```python
"""
Kubernetes Manifest background tasks.
It is used to apply and delete Kubernetes resources defined in a manifest.
"""

import frappe

from kubeport.utils.k8s_client import get_k8s_api_client
from kubeport.utils.k8s_resources import apply_resource, delete_resource, parse_manifest_objects


def apply_manifest_task(manifest_name: str):
	"""Background task: apply a Kubernetes manifest to the cluster.

	Uses server-side apply for idempotency — re-applying an already-deployed
	manifest updates it instead of failing with a 409 Conflict.
	"""
	doc = frappe.get_doc("Kubernetes Manifest", manifest_name)

	try:
		api_client = get_k8s_api_client(doc.cluster)
		manifest_data = parse_manifest_objects(doc.content)
		namespace = doc.namespace or "default"

		for k8s_object in manifest_data:
			apply_resource(api_client, k8s_object, namespace)

		doc.db_set("status", "Applied")

		frappe.publish_realtime(
			"manifest_status_update",
			{"manifest_name": manifest_name, "status": "Applied"},
			doctype="Kubernetes Manifest",
			docname=manifest_name,
		)

	except Exception as e:
		doc.db_set("status", "Failed")
		frappe.log_error(
			title=f"Manifest Apply Failed: {manifest_name}",
			message=str(e),
		)
		frappe.publish_realtime(
			"manifest_status_update",
			{"manifest_name": manifest_name, "status": "Failed"},
			doctype="Kubernetes Manifest",
			docname=manifest_name,
		)


def delete_manifest_task(manifest_name: str):
	"""Background task: delete Kubernetes resources defined in a manifest."""
	doc = frappe.get_doc("Kubernetes Manifest", manifest_name)

	try:
		api_client = get_k8s_api_client(doc.cluster)
		manifest_data = parse_manifest_objects(doc.content)

		for k8s_object in manifest_data:
			delete_resource(api_client, k8s_object, doc.namespace or "default")

		doc.db_set("status", "Draft")

		frappe.publish_realtime(
			"manifest_status_update",
			{"manifest_name": manifest_name, "status": "Draft"},
			doctype="Kubernetes Manifest",
			docname=manifest_name,
		)

	except Exception as e:
		doc.db_set("status", "Failed")
		frappe.log_error(
			title=f"Manifest Delete Failed: {manifest_name}",
			message=str(e),
		)
		frappe.publish_realtime(
			"manifest_status_update",
			{"manifest_name": manifest_name, "status": "Failed"},
			doctype="Kubernetes Manifest",
			docname=manifest_name,
		)
```
</details>
