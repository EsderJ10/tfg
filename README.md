## TODO

### Hito 1: Setup Inicial, Infraestructura y Arquitectura Base
*Objetivo: Tener los cimientos listos y el entorno de desarrollo preparado para la primera validación.*

- [ ] **Task 1: Definición de la arquitectura y diseño de Base de Datos**
  - **Prioridad:** Alta | **Estado:** Done | [cite_start]**Asignado a:** Todos [cite: 18]
- [ ] **Task 2: Aprovisionamiento del clúster y red (IaC)**
  - **Prioridad:** Alta | **Estado:** In Progress | [cite_start]**Asignado a:** [DevOps] [cite: 18]
  - [ ] [cite_start]Task 2.1: Scripts de Terraform para provisionar clúster K8s (1 Master, 2 Workers). [cite: 20]
  - [ ] [cite_start]Task 2.2: Configuración inicial de Helm, NGINX Ingress y Cert-Manager (Let's Encrypt). [cite: 20]
- [ ] **Task 3: Setup del Backend y Base de Datos**
  - **Prioridad:** Alta | **Estado:** To Do | [cite_start]**Asignado a:** [Backend] [cite: 18]
  - [ ] [cite_start]Task 3.1: Inicializar proyecto FastAPI y configurar conexión a PostgreSQL. [cite: 20]
  - [ ] [cite_start]Task 3.2: Implementar modelos ORM (Users, Clusters, Benches, Sites). [cite: 20]
- [ ] **Task 4: Setup del Frontend y Enrutamiento**
  - **Prioridad:** Alta | **Estado:** To Do | [cite_start]**Asignado a:** [Frontend] [cite: 18]
  - [ ] [cite_start]Task 4.1: Inicializar React (Vite/Next.js) e instalar Tailwind CSS. [cite: 20]
  - [ ] [cite_start]Task 4.2: Crear el layout principal (Sidebar, Header, enrutador base). [cite: 20]

---

### Hito 2: Core del Orquestador y Lógica de Negocio
*Objetivo: El backend debe poder comunicarse de forma segura con la API de Kubernetes.*

- [ ] **Task 5: Imágenes y Helm Charts (DevOps)**
  - **Prioridad:** Alta | **Estado:** To Do | [cite_start]**Asignado a:** [DevOps] [cite: 18]
  - [ ] [cite_start]Task 5.1: Crear imagen Docker base con Frappe + Custom Libraries. [cite: 20]
  - [ ] [cite_start]Task 5.2: Desarrollar Helm Chart base para desplegar un *Bench* completo. [cite: 20]
- [ ] **Task 6: Integración K8s y Auth (Backend)**
  - **Prioridad:** Alta | **Estado:** To Do | [cite_start]**Asignado a:** [Backend] [cite: 18]
  - [ ] [cite_start]Task 6.1: Desarrollar endpoints de Login/Registro (JWT). [cite: 20]
  - [ ] [cite_start]Task 6.2: Integrar librería `kubernetes-client` en FastAPI. [cite: 20]
  - [ ] [cite_start]Task 6.3: Endpoint para listar *namespaces* y *pods* de un bench (`kubectl get pods -n <namespace>`). [cite: 20]

---

### Hito 3: Despliegue Dinámico y Funcionalidad Clave
*Objetivo: El usuario debe poder crear un nuevo sitio desde el dashboard y orquestarlo en K8s.*

- [ ] **Task 7: Vistas y Conexión API (Frontend)**
  - **Prioridad:** Media | **Estado:** To Do | [cite_start]**Asignado a:** [Frontend] [cite: 18]
  - [ ] [cite_start]Task 7.1: Implementar pantalla de Login y protección de rutas. [cite: 20]
  - [ ] [cite_start]Task 7.2: Maquetar tabla para listar Benches y Sitios consumiendo la API. [cite: 20]
- [ ] **Task 8: Orquestación de Creación de Sitios**
  - **Prioridad:** Alta | **Estado:** To Do | [cite_start]**Asignado a:** [Backend y DevOps] [cite: 18]
  - [ ] [cite_start]Task 8.1: Crear endpoint POST que reciba el dominio y apps seleccionadas. [cite: 20]
  - [ ] [cite_start]Task 8.2: Diseñar el K8s Job (contenedor desechable) que ejecuta `bench new-site`. [cite: 20]
- [ ] **Task 9: Formularios de Creación (Frontend)**
  - **Prioridad:** Alta | **Estado:** To Do | [cite_start]**Asignado a:** [Frontend] [cite: 18]
  - [ ] [cite_start]Task 9.1: Diseñar formulario modal para "Nuevo Bench". [cite: 20]
  - [ ] [cite_start]Task 9.2: Formulario de "Nuevo Sitio" (Dominio -> Apps -> Confirmar). [cite: 20]

---

### Hito 4: Telemetría, Pruebas y Pre-Entrega
*Objetivo: Pulir telemetría, testear tolerancia a fallos y preparar la entrega final.*

- [ ] **Task 10: Telemetría y UI en Tiempo Real**
  - **Prioridad:** Media | **Estado:** To Do | [cite_start]**Asignado a:** [Backend y Frontend] [cite: 18]
  - [ ] [cite_start]Task 10.1: Endpoint para obtener el estado real de un Pod (Pending, Running, Failed). [cite: 20]
  - [ ] [cite_start]Task 10.2: Mostrar *badges* de estado en la UI del dashboard. [cite: 20]
- [ ] **Task 11: Pruebas de Resiliencia y Entrega**
  - **Prioridad:** Alta | **Estado:** To Do | [cite_start]**Asignado a:** Todos [cite: 18]
  - [ ] [cite_start]Task 11.1: Simular caída de nodos/pods y documentar auto-sanación (*self-healing*). [cite: 20]
  - [ ] [cite_start]Task 11.2: Revisión final de código y limpieza del repositorio. [cite: 20]