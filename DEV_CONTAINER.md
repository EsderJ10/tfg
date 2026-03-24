# Frappe Control Plane para Kubernetes (v16): DEV CONTAINER

## 1. Configuración del Bench y Sitio

### Crear el Bench
```bash
bench init bench-16 --frappe-branch version-16 --skip-redis-config-generation
```

### Configurar Hosts de Docker
Necesario para que el bench encuentre los servicios dentro de la red del Dev Container:
```bash
cd bench-16

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
# License: MIT
# App Publisher: Los Favs
# Ignorar Github CI/CD workflow por ahora.
```

### Instalar y Activar Modo Desarrollador
```bash
bench --site frappe-k8s.localhost install-app kubeport
bench --site frappe-k8s.localhost set-config developer_mode 1
```

## 3. Infraestructura Kubernetes (K3d)

### Instalación de K3d

```bash
# Curl
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Wget
wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Referencia
# https://github.com/k3d-io/k3d
```

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

### LINUX

1.  **Obtener IP del Gateway:** Ejecutar `python -c "import socket; print(socket.gethostbyname(socket.gethostname()))"` en la terminal del contenedor. Si da `172.22.0.4`, usar `172.22.0.1`.
2.  **Editar Server en Frappe:** * `server: https://<DIRECCIÓN_IP>:46469`

### WINDOWS (Docker Desktop)

En Windows, las restricciones del Firewall y el aislamiento de red de WSL2 a menudo bloquean las peticiones del contenedor hacia el host (Errores 101, 113 o Connection Refused). La solución definitiva es conectar ambos contenedores a la misma red virtual de Docker para que se comuniquen de forma directa.

1.  **Identificar el contenedor de Frappe:**
    Abre una terminal en Windows (PowerShell o CMD) y ejecuta:
    ```bash
    docker ps
    ```
    Busca el nombre asignado a tu contenedor de Frappe (usualmente algo como `<NOMBRE_DEL_CONTENEDOR>-frappe-1`).

2.  **Unir Frappe a la red de K3d:**
    En la misma terminal de Windows, conecta tu contenedor a la red que K3d creó para el clúster:
    ```bash
    docker network connect k3d-frappe-cluster <NOMBRE_DEL_CONTENEDOR_FRAPPE>
    ```

3.  **Editar Server en Frappe (DNS interno):**
    Al estar en la misma red, Frappe ya no necesita salir a Windows. Puede hablar directamente con el balanceador de carga interno de K3d usando su nombre DNS interno y el puerto nativo de Kubernetes (`6443`), ignorando el puerto aleatorio expuesto en el host.
    
    Edita la línea del servidor en el Kubeconfig de tu DocType:
    * `server: https://k3d-frappe-cluster-serverlb:6443`

## 7. Ejecución de comandos (kubectl) desde la interfaz de Frappe

Para interactuar dinámicamente con los clústeres desde Frappe, necesitamos instalar `kubectl` en el contenedor y crear un DocType que actúe como terminal interactiva.

### 7.1. Instalación de `kubectl` en el Dev Container

Ejecutar dentro de la terminal del Dev Container (VS Code):

```bash
curl -LO "[https://dl.k8s.io/release/$(curl](https://dl.k8s.io/release/$(curl) -L -s [https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl](https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl)"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client # Para verificar la instalación
```

## 7.2. DocType: Kubernetes Command

Crear un nuevo DocType en el módulo Kubeport con las siguientes propiedades:

- **Naming Rule:** By fieldname  
- **Autoname:** command_name  

### Campos (Layout):

| Label           | Type   | Name            | Mandatory | Options / Notas                                      |
|----------------|--------|-----------------|----------|------------------------------------------------------|
| Name           | Data   | command_name    | ✅        | Nombre descriptivo (ej. "Listar Pods").             |
| Target Cluster | Link   | cluster         | ✅        | Options: Kubernetes Cluster                         |
| Command        | Data   | command         | ✅        | Comando a ejecutar (ej. `get pods -A`).             |
| Execute        | Button | execute_command | ❌        | Disparador de la ejecución.                         |
| Output         | Code   | output          | ❌        | Read Only. Options: Markdown o JSON.                |

---

## 7.3. Lógica de Ejecución (Código)

El script toma el Kubeconfig guardado en el clúster vinculado, lo inyecta en un archivo temporal y usa la librería `subprocess` para ejecutar `kubectl` en el sistema base de forma segura.

### Backend (Python)

**Ubicación:**  
`apps/kubeport/kubeport/kubeport/doctype/kubernetes_command/kubernetes_command.py`

```python
import frappe
from frappe.model.document import Document
import subprocess
import tempfile
import os

class KubernetesCommand(Document):
    @frappe.whitelist()
    def execute_command(self):
        if not self.cluster or not self.command:
            frappe.throw("El clúster y el comando son obligatorios.")

        # 1. Recuperar el Kubeconfig del clúster seleccionado
        cluster_doc = frappe.get_doc("Kubernetes Cluster", self.cluster)
        if not cluster_doc.kubeconfig:
            frappe.throw("El clúster seleccionado no tiene un Kubeconfig guardado.")

        # 2. Limpieza de UX (por si el usuario incluye 'kubectl' en el input)
        cmd_string = self.command.strip()
        if cmd_string.startswith("kubectl "):
            cmd_string = cmd_string[8:]
            
        cmd_args = cmd_string.split()

        # 3. Crear archivo temporal seguro para el Kubeconfig
        fd, temp_path = tempfile.mkstemp(suffix=".yaml")
        
        try:
            with os.fdopen(fd, 'w') as f:
                f.write(cluster_doc.kubeconfig)

            # 4. Preparar comando ignorando verificación TLS local
            full_cmd = ["kubectl", "--kubeconfig", temp_path, "--insecure-skip-tls-verify=true"] + cmd_args

            # 5. Ejecutar comando en el shell del contenedor
            result = subprocess.run(full_cmd, capture_output=True, text=True)

            # 6. Almacenar el output (sea de éxito o de error)
            output_text = result.stdout if result.returncode == 0 else result.stderr
            self.db_set('output', output_text)

            if result.returncode == 0:
                frappe.msgprint("Comando ejecutado con éxito", indicator="green", alert=True)
            else:
                frappe.msgprint("El comando devolvió un error. Revisa el campo Output.", indicator="red", alert=True)

        except Exception as e:
            frappe.throw(f"Error interno al ejecutar el comando: {str(e)}")
            
        finally:
            # 7. Limpiar siempre el archivo temporal
            if os.path.exists(temp_path):
                os.remove(temp_path)
```

### Frontend (JavaScript)

**Ubicación:**  
`apps/kubeport/kubeport/kubeport/doctype/kubernetes_command/kubernetes_command.js`

```javascript
frappe.ui.form.on('Kubernetes Command', {
    execute_command: function(frm) {
        if (!frm.doc.cluster || !frm.doc.command) {
            frappe.msgprint(__('Por favor, selecciona un clúster y escribe un comando.'));
            return;
        }

        frappe.call({
            doc: frm.doc,
            method: 'execute_command',
            freeze: true,
            freeze_message: __('Ejecutando en el clúster...'),
            callback: function(r) {
                if (!r.exc) {
                    frm.reload_doc(); // Recarga para actualizar y ver el campo Output
                }
            }
        });
    }
});
```