# TAREAS 16/04/2026

- TAREA 1: Live discovery de benches y sitios en un clúster:
    - José Luis propuso hacerlo con Virtual DocTypes.
    - **Implementación actual:** En el vídeo que mandamos, se demostró usando "live queries".
    - **Validación del Enfoque (Virtual DocTypes vs Client-side queries):**
      - Lo hice así con la base conceptual de NO guardar en la base de datos para evitar problemas de sincronización (split-brain) entre Frappe y el clúster de K8s. 
      - De esta manera, separamos explícitamente el estado deseado -el de MariaDB- con el estado real -el de K8s-. 

- TAREA 2: Creación de sitios y benches desde la UI:
    - José Luis nos ha comentado que esto se hace mediante *Jobs de Helm Chart de ERPNext*.
    - **Investigación:** En base a lo que he estado mirando, esto parece ser viable y el estándar.
      1. Helm despliega "Benches" empaquetando configuraciones globales (`Deployment` workers, Gunicorn, Nginx, Redis).
      2. Helm provee mecanismos intrínsecos ("Helm Hooks") para inyectar *Kubernetes Jobs*.
      3. A nivel Chart de ERPNext Oficial, la pipeline provee la creación de sitios vía `create-site` Job.
      4. EL objetivo de Kubeport es abstraer esta complejidad al usuario: Tomar credenciales, reescribir la sección `jobs.createSite...` dentro de la variable de valores y ejecutar `helm upgrade`.
      5. La base K8s se encargará del resto, ejecutando de fondo el Job (un pod temporal) con el comando `bench new-site...`. Kubeport luego leerá en "Live discovery" que el Job terminó o falló para retroalimentar la UI.