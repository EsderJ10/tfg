# Kubeport — Stack de Evaluación

Este directorio contiene un *stack* de despliegue completo basado en Docker
Compose pensado **para evaluadores**: levanta Kubeport, su bench Frappe y un
clúster Kubernetes embebido (k3s) con un único comando, y lo deja pre-configurado
para que se pueda probar Kubeport contra ese clúster sin instalar nada en el
equipo anfitrión más allá de Docker.

> Si lo que buscas es un entorno de **desarrollo** (con dev-container y
> recarga en caliente), usa `devcontainer-example/` en la raíz del repositorio
> *paraguas* (`tfg`). Este `deploy/` es para correr la app, no para editarla.

---

## 1. Componentes del *stack*

| Servicio | Imagen / Build | Rol |
|---|---|---|
| `mariadb` | `mariadb:11.8` | Base de datos del bench Frappe (estado deseado de Kubeport). |
| `redis-cache` | `redis:7-alpine` | Caché del framework. |
| `redis-queue` | `redis:7-alpine` | Cola RQ + bus de socket.io. |
| `k3s` | `rancher/k3s:v1.30.4-k3s1` | Clúster Kubernetes de un nodo, expuesto al bench y al *host* en el puerto 6443. |
| `kubeport` | Construido localmente desde `images/kubeport/Dockerfile` | Bench Frappe v16 con `kubeport`, helm 3 y un *entrypoint* que crea el sitio y registra el clúster k3s automáticamente. |

La red interna de Compose conecta los cinco servicios. El bench llega a k3s
por `https://k3s:6443` y a MariaDB / Redis por sus nombres de servicio.

---

## 2. Requisitos del equipo evaluador

- **Docker Engine ≥ 24** y **Docker Compose v2** (incluido en Docker Desktop).
- **8 GB de RAM** disponibles para la VM/host de Docker (k3s + Frappe juntos
  usan ~3 GB en reposo y picos de 4–5 GB durante el primer arranque).
- **15 GB de disco** libres (imágenes + volúmenes persistentes).
- Puertos libres en el *host*: `8000` (Frappe), `9000` (socket.io), `6443`
  (API de k3s, opcional). Se pueden reasignar con variables de entorno.
- Conexión a internet la primera vez (descarga de imágenes y *clone* del
  repositorio de Kubeport).

No se requiere `kubectl`, ni `helm`, ni Python, ni Node en el *host*.

---

## 3. Despliegue rápido (3 comandos)

```bash
cd tfg/deploy
docker compose build kubeport      # ~5–10 min la primera vez
docker compose up -d
```

La primera vez que el bench arranca, su *entrypoint*:

1. Espera a que MariaDB, los dos Redis y k3s estén listos.
2. Ejecuta `bench new-site kubeport.localhost --install-app kubeport` (≈ 60 s).
3. Lee el kubeconfig que k3s ha escrito en el volumen compartido y le sustituye
   el *server* `127.0.0.1` por `k3s` para que sea alcanzable desde el bench.
4. Inserta una fila `Kubernetes Cluster` llamada `eval-k3s` apuntando a ese
   kubeconfig (con `Skip TLS Verify` activado porque el certificado de k3s es
   autofirmado).
5. Inicia `bench start` (web + worker + scheduler).

A partir del segundo arranque, todo lo anterior se omite (es idempotente).

Comprobar el estado:

```bash
docker compose ps
docker compose logs -f kubeport
```

Cuando `docker compose logs -f kubeport` muestre `bench start` y la línea
`Watching for changes`, el bench está sirviendo.

---

## 4. Acceso al bench

- URL: <http://localhost:8000>
- Sitio: `kubeport.localhost` (servido como sitio por defecto del bench)
- Usuario: `Administrator`
- Contraseña: `admin` (configurable vía `ADMIN_PASSWORD` en `.env`)

Tras iniciar sesión, el menú lateral muestra **Kubeport Operations**. Esa
*workspace* es la portada operativa: tarjetas de salud, donas de distribución
de estado, gráfica diaria de operaciones Helm y atajos a cada DocType.

---

## 5. Recorrido de evaluación sugerido (~10 min)

El objetivo es verificar las características que el TFG destaca como
innovadoras: descubrimiento *live*, despliegue de Helm con bundle de MariaDB,
ciclo de vida de sitios Frappe vía Kubernetes Jobs, *backups* programados.

### 5.1 Descubrimiento *live* del clúster

1. Ir a **Kubernetes Cluster** → fila `eval-k3s` → botón **Test Connection**.
   Debe responder *Connected*.
2. En esa misma fila, la sección de descubrimiento muestra los Helm releases
   y *namespaces* del clúster. En un k3s recién levantado verás `kube-system`.

### 5.2 Registrar un repositorio Helm y desplegar una release

1. **Helm Repository** → New → `Repository Name = bitnami`,
   `URL = https://charts.bitnami.com/bitnami`. Guardar.
2. La sincronización corre en *background*; el campo `Sync Status` pasa a
   `Synced` en menos de un minuto.
3. **Helm Release** → New →
   - `Cluster = eval-k3s`
   - `Namespace = demo`
   - `Release Name = nginx-demo`
   - `Chart = bitnami/nginx`
   - Pulsar **Deploy**.
4. La fila pasa por `Draft → In Progress → Deployed`. El *drilldown* de
   *workload readiness* muestra los pods, eventos y *rollout context* en
   tiempo real.

### 5.3 Crear un sitio Frappe sobre un release ERPNext

1. **Helm Repository** → New → `frappe = https://helm.erpnext.com`.
2. **Helm Release** → New →
   - `Chart = frappe/erpnext`
   - **Use External Database** *desmarcado* (Kubeport instalará MariaDB sibling
     automáticamente).
   - Marcar **Enable Ingress**, escribir un *hostname* del estilo
     `erp.<ip-de-k3s>.nip.io`. **Deploy**.
3. Una vez `Deployed`, **Frappe Site** → New →
   - `Bench Release = <la fila anterior>`
   - `Site Name = demo.localhost`
   - **Create Site**.
4. La fila pasa `Draft → In Progress → Active`. Por debajo, Kubeport ha
   ejecutado un *Job* clonado del pod del bench corriendo `bench new-site`
   contra el MariaDB *sibling*.

> El stack de evaluación **no expone** ese ingress al *host* por defecto
> (k3s no incluye un controlador de ingress en este perfil). El propósito
> del paso 3 es demostrar el flujo de creación de sitios y el *drilldown*
> de observabilidad, no servir tráfico HTTP del sitio Frappe creado.

### 5.4 *Backups* programados

1. En la fila `demo.localhost` → sección **Backups**.
2. **Backup Schedule** = `*/10 * * * *` (cada 10 minutos),
   **Retention: Max Backups** = `3`. Guardar.
3. La pestaña *Backups* mostrará nuevas filas `Available` cada 10 minutos;
   el *retention* poda las antiguas automáticamente.

---

## 6. Variables de entorno

Copia `.env.example` a `.env` para sobreescribir cualquier valor:

```bash
cp .env.example .env
```

| Variable | Por defecto | Descripción |
|---|---|---|
| `SITE_NAME` | `kubeport.localhost` | Nombre del sitio Frappe (también es el *host header*). |
| `ADMIN_PASSWORD` | `admin` | Contraseña del usuario `Administrator`. |
| `MARIADB_ROOT_PASSWORD` | `changeme` | Contraseña de root de MariaDB. **Cámbiala fuera de demo local.** |
| `K3S_CLUSTER_NAME` | `eval-k3s` | Nombre de la fila `Kubernetes Cluster` que el seed deja insertada. |
| `BENCH_HOST_PORT` | `8000` | Puerto del *host* mapeado al web de Frappe. |
| `BENCH_SOCKETIO_PORT` | `9000` | Puerto del *host* mapeado al socket.io de Frappe. |
| `K3S_HOST_PORT` | `6443` | Puerto del *host* mapeado a la API de k3s (para `kubectl` desde fuera). |
| `KUBEPORT_REPO` / `KUBEPORT_REF` | `EsderJ10/kubeport`, `main` | Origen y *ref* de Kubeport que se hornea en la imagen. Para la entrega final, fijar `KUBEPORT_REF` a un *tag*. |

---

## 7. Operaciones cotidianas

Hay un `Makefile` con atajos sobre los comandos más usados:

```bash
make build       # construye la imagen del bench (la primera vez)
make up          # arranca el stack
make down        # detiene el stack (mantiene volúmenes)
make nuke        # detiene y borra TODOS los volúmenes
make logs        # tail de logs de todos los servicios
make logs-bench  # tail solo del bench
make logs-k3s    # tail solo de k3s
make shell       # entra en el contenedor del bench
make kubeconfig  # imprime el kubeconfig de k3s adaptado al host (para usar con kubectl desde fuera)
make status      # docker compose ps
```

Si no tienes `make`, todos los comandos equivalentes están en el Makefile —
son una línea cada uno.

### *Reset* completo

```bash
make nuke
make up
```

Borra MariaDB, Redis, k3s y los *sites*; el siguiente arranque es el *first-run*
otra vez (~2 min).

---

## 8. Acceder al clúster k3s desde el *host*

```bash
make kubeconfig > /tmp/eval-kubeconfig.yaml
export KUBECONFIG=/tmp/eval-kubeconfig.yaml
kubectl get nodes
kubectl get pods -A
```

Útil para inspeccionar lo que Kubeport está haciendo "por debajo": los Jobs
de `bench new-site`, los Secrets generados con las credenciales, el PVC de
*backups*, el *ingress* que Kubeport renderiza, etc.

---

## 9. Solución de problemas

### `kubeport` se queda en `unhealthy` durante el primer arranque

Es esperable los primeros 90–120 s mientras `bench new-site` ejecuta. Sigue
los logs:

```bash
docker compose logs -f kubeport
```

La línea `[entrypoint] site kubeport.localhost ready` señala el final del
*first-run*.

### El `Test Connection` de la fila `eval-k3s` da `Error`

Comprobar que k3s arrancó:

```bash
docker compose ps k3s
docker compose logs k3s | tail -50
```

Si k3s no llegó a estado *healthy*, puede ser falta de RAM/CPU en el *host*
de Docker. Aumenta los recursos asignados a Docker Desktop o reinicia el
*stack* completo (`make nuke && make up`).

### Quiero usar mi propio clúster en lugar del k3s embebido

Edita la fila `eval-k3s` (o crea otra) en **Kubernetes Cluster**, cambia el
*Auth Method* a `Kubeconfig` y pega tu kubeconfig. Kubeport **ya soporta**
varios clústeres conviviendo, no hay que apagar el k3s embebido para hacerlo.

### Quiero detener el k3s embebido (sólo bench Frappe)

```bash
docker compose stop k3s
```

El bench y la UI siguen sirviendo; lo único que dejará de funcionar es el
*Test Connection* contra `eval-k3s`.

---

## 10. Para la defensa del TFG

El TFG pide ([brief] en español):

> *Documentación del proyecto, descripción funcional, modelo de datos final,
> stack tecnológico, instrucciones de despliegue (preferiblemente en docker,
> por lo que podría ser necesario contar con un repositorio adicional en el
> que se encuentren los archivos docker compose), código fuente.*

Este `deploy/` es el componente **"instrucciones de despliegue (en docker)"**.
Los demás componentes están donde se espera:

| Requisito del *brief* | Dónde está |
|---|---|
| Documentación del proyecto y descripción funcional | [`kubeport/README.md`](https://github.com/EsderJ10/kubeport/blob/main/README.md) y [`kubeport/docs/`](https://github.com/EsderJ10/kubeport/tree/main/docs) |
| Modelo de datos final | [`kubeport/docs/architecture.md#4-doctype-map-components`](https://github.com/EsderJ10/kubeport/blob/main/docs/architecture.md#4-doctype-map-components) |
| Stack tecnológico y arquitectura | [`kubeport/docs/architecture.md`](https://github.com/EsderJ10/kubeport/blob/main/docs/architecture.md) |
| Instrucciones de despliegue (Docker) | **este directorio** |
| Despliegue para producción (no demo) | [`kubeport/docs/deploy.md`](https://github.com/EsderJ10/kubeport/blob/main/docs/deploy.md) |
| Código fuente | [`EsderJ10/kubeport`](https://github.com/EsderJ10/kubeport) — fija `KUBEPORT_REF` al *tag* de entrega antes de construir. |

---

## 11. Qué *no* hace este *stack*

Es un entorno de evaluación, no de producción:

- No expone `https://` ni gestiona certificados; el bench corre en HTTP plano
  en `localhost:8000`.
- No hay *ingress controller* en el k3s (se *opta-out* con `--disable=traefik`
  para no añadir 200 MB de imagen y un mapeo de puertos extra). Para evaluar
  la característica de *ingress* de Kubeport, basta con verla configurada en
  el formulario de Helm Release; el tráfico real no se propaga al *host*.
- No realiza *backups* del bench Frappe ni del *state* de k3s al *host*.
- No está endurecido (las contraseñas viven en `.env` en texto plano).

Para una guía de despliegue en producción ver
[`kubeport/docs/deploy.md`](https://github.com/EsderJ10/kubeport/blob/main/docs/deploy.md).
