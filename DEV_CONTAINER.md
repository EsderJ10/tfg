# Frappe Control Plane para Kubernetes (v16): DEV CONTAINER


## 1. Configuración del Bench y Sitio

### Crear el Bench
```bash
bench init bench-16 --frappe-branch version-16
cd bench-16
```

### Configurar Hosts de Docker
Necesario para que el bench encuentre los servicios dentro de la red del Dev Container:
```bash
bench set-config -g db_host mariadb
bench set-config -g redis_cache redis://redis-cache:6379
bench set-config -g redis_queue redis://redis-queue:6379
bench set-config -g redis_socketio redis://redis-queue:6379
```

### Crear e Instalar el Sitio
```bash
bench new-site frappe-k8s.localhost --mariadb-root-password 123 --admin-password admin
bench start
```

## 2. Configuración de la Aplicación Custom

### Crear la App
```bash
bench new-app kubeport
# Detalles:
# App Name: kubeport
# Description: A centralized Kubernetes Control Plane.
# App Publisher: Los Favs
# License: MIT
```

### Instalar y Activar Modo Desarrollador
```bash
bench --site frappe-k8s.localhost install-app kubeport
bench --site frappe-k8s.localhost set-config developer_mode 1
```

## 3. Infraestructura Kubernetes (K3d)

### Crear el Clúster
Ejecutar en la terminal de la máquina host (o donde esté instalado K3d):
```bash
k3d cluster create frappe-cluster
```

### Obtener Credenciales
```bash
k3d kubeconfig get frappe-cluster
```


## 4. DocType: Kubernetes Cluster

Crear un nuevo DocType en el módulo **Kubeport** con las siguientes propiedades:

* **Naming Rule:** `By fieldname`
* **Autoname:** `cluster_name`

### Campos (Layout)
| Label | Type | Name | Mandatory | Options / Notas |
| :--- | :--- | :--- | :---: | :--- |
| **Cluster Name** | Data | `cluster_name` | ✅ | Marcar como **Unique**. |
| **Kubeconfig** | Code | `kubeconfig` | ✅ | **Options:** `JSON` (YAML no es válido en v16). |
| **Test Connection** | Button | `test_connection` | ❌ | Disparador de la lógica de conexión. |
| **Status** | Select | `status` | ❌ | `Pending`, `Connected`, `Error`. **Read Only**. |


## 5. Lógica de Conexión (Código)

### Requisito: Instalar librería de Python
```bash
./env/bin/pip install kubernetes
```

### Backend (Python)
**Ubicación:** `apps/kubeport/kubeport/kubeport/doctype/kubernetes_cluster/kubernetes_cluster.py`

```python
import frappe
from frappe.model.document import Document
from kubernetes import client, config
import yaml
import urllib3

class KubernetesCluster(Document):
    @frappe.whitelist()
    def test_connection(self):
        if not self.kubeconfig:
            frappe.throw("El campo Kubeconfig está vacío.")

        try:
            # 1. Cargar configuración
            kubeconfig_dict = yaml.safe_load(self.kubeconfig)
            config.load_kube_config_from_dict(kubeconfig_dict)
            
            # 2. Bypass de Seguridad SSL para entornos locales
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
            conf = client.Configuration.get_default_copy()
            conf.verify_ssl = False
            client.Configuration.set_default(conf)
            
            # 3. Validar conexión listando nodos
            v1 = client.CoreV1Api()
            nodes = v1.list_node()
            
            self.db_set('status', 'Connected')
            frappe.msgprint(f"¡Conexión exitosa! Nodos detectados: {len(nodes.items)}", indicator='green')
            
        except Exception as e:
            self.db_set('status', 'Error')
            frappe.throw(f"Fallo al conectar: {str(e)}")
```

### Frontend (JavaScript)
**Ubicación:** `apps/kubeport/kubeport/kubeport/doctype/kubernetes_cluster/kubernetes_cluster.js`

```javascript
frappe.ui.form.on('Kubernetes Cluster', {
    test_connection: function(frm) {
        frappe.call({
            doc: frm.doc,
            method: 'test_connection',
            freeze: true,
            freeze_message: __('Connecting to Cluster...'),
            callback: function(r) {
                if (!r.exc) {
                    frm.reload_doc();
                }
            }
        });
    }
});
```


## 6. Solución de Problemas de Red (Gateway)

Para que el contenedor de Frappe llegue al Host (K3d), se debe modificar la URL del `server` en el Kubeconfig pegado en Frappe:

1.  **Obtener IP del Gateway:** Ejecutar `python -c "import socket; print(socket.gethostbyname(socket.gethostname()))"` en la terminal del contenedor. Si da `172.22.0.4`, usar `172.22.0.1`.
2.  **Editar Server en Frappe:** * `server: https://172.22.0.1:46469` (Linux)
    * Hay que investigar.