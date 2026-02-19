## TODO

### Hito 1: Setup Inicial, Infraestructura y Arquitectura Base
*Objetivo: Tener los cimientos listos y el entorno de desarrollo preparado para la primera validación.*

- [ ] **Task 1: Definición de la arquitectura y diseño de Base de Datos**
  - **Prioridad:** Alta | **Asignado a:**
- [ ] **Task 2: Aprovisionamiento del clúster y red (IaC)**
  - **Prioridad:** Alta | **Asignado a:**  
  - [ ] Task 2.1: Scripts de Terraform para provisionar clúster K8s (1 Master, 2 Workers). 
  - [ ] Task 2.2: Configuración inicial de Helm, NGINX Ingress y Cert-Manager (Let's Encrypt). 
- [ ] **Task 3: Setup del Backend y Base de Datos**
  - **Prioridad:** Alta | **Asignado a:**  
  - [ ] Task 3.1: Inicializar proyecto FastAPI y configurar conexión a PostgreSQL. 
  - [ ] Task 3.2: Implementar modelos ORM (Users, Clusters, Benches, Sites). 
- [ ] **Task 4: Setup del Frontend y Enrutamiento**
  - **Prioridad:** Alta | **Asignado a:**  
  - [ ] Task 4.1: Inicializar React (Vite/Next.js) e instalar Tailwind CSS. 
  - [ ] Task 4.2: Crear el layout principal (Sidebar, Header, enrutador base). 

---

### Hito 2: Core del Orquestador y Lógica de Negocio
*Objetivo: El backend debe poder comunicarse de forma segura con la API de Kubernetes.*

- [ ] **Task 5: Imágenes y Helm Charts (DevOps)**
  - **Prioridad:** Alta |  **Asignado a:**  
  - [ ] Task 5.1: Crear imagen Docker base con Frappe + Custom Libraries. 
  - [ ] Task 5.2: Desarrollar Helm Chart base para desplegar un *Bench* completo. 
- [ ] **Task 6: Integración K8s y Auth (Backend)**
  - **Prioridad:** Alta |  **Asignado a:**  
  - [ ] Task 6.1: Desarrollar endpoints de Login/Registro (JWT). 
  - [ ] Task 6.2: Integrar librería `kubernetes-client` en FastAPI. 
  - [ ] Task 6.3: Endpoint para listar *namespaces* y *pods* de un bench. 

---

### Hito 3: Despliegue Dinámico y Funcionalidad Clave
*Objetivo: El usuario debe poder crear un nuevo sitio desde el dashboard y orquestarlo en K8s.*

- [ ] **Task 7: Vistas y Conexión API (Frontend)**
  - **Prioridad:** Media |  **Asignado a:**  
  - [ ] Task 7.1: Implementar pantalla de Login y protección de rutas. 
  - [ ] Task 7.2: Maquetar tabla para listar Benches y Sitios consumiendo la API. 
- [ ] **Task 8: Orquestación de Creación de Sitios**
  - **Prioridad:** Alta |  **Asignado a:** 
  - [ ] Task 8.1: Crear endpoint POST que reciba el dominio y apps seleccionadas. 
  - [ ] Task 8.2: Diseñar el K8s Job (contenedor desechable) que ejecuta `bench new-site`. 
- [ ] **Task 9: Formularios de Creación (Frontend)**
  - **Prioridad:** Alta |  **Asignado a:**  
  - [ ] Task 9.1: Diseñar formulario modal para "Nuevo Bench". 
  - [ ] Task 9.2: Formulario de "Nuevo Sitio" (Dominio -> Apps -> Confirmar). 

---

### Hito 4: Telemetría, Pruebas y Pre-Entrega
*Objetivo: Pulir telemetría, testear tolerancia a fallos y preparar la entrega final.*

- [ ] **Task 10: Telemetría y UI en Tiempo Real**
  - **Prioridad:** Media |  **Asignado a:**  
  - [ ] Task 10.1: Endpoint para obtener el estado real de un Pod (Pending, Running, Failed). 
  - [ ] Task 10.2: Mostrar *badges* de estado en la UI del dashboard. 
- [ ] **Task 11: Pruebas de Resiliencia y Entrega**
  - **Prioridad:** Alta |  **Asignado a:**  
  - [ ] Task 11.1: Simular caída de nodos/pods y documentar auto-sanación (*self-healing*). 
  - [ ] Task 11.2: Revisión final de código y limpieza del repositorio. 