# CONTROL PLANE FRAPPE K8S

## Componentes del proyecto

Este repositorio es el paraguas del TFG. El entregable completo se compone de tres repositorios:

| Componente | Repositorio | Rol |
|---|---|---|
| Backend / app | [`EsderJ10/kubeport`](https://github.com/EsderJ10/kubeport) | Aplicación Frappe que actúa como plano de control de Kubernetes. |
| Landing page | [`1DAW-victorjim551/lp-KubePort`](https://github.com/1DAW-victorjim551/lp-KubePort) | Página pública del proyecto, desplegada en [`1daw-victorjim551.github.io/lp-KubePort`](https://1daw-victorjim551.github.io/lp-KubePort/). Autoría de Víctor Jiménez. |
| Umbrella (este repo) | `EsderJ10/tfg` | Dev-container, *stack* de despliegue Docker para evaluación, documentación de diseño, task tracker. |

Para el marco académico (problema, estado del arte, objetivos, resultados) ver [`docs/thesis.md`](https://github.com/EsderJ10/kubeport/blob/main/docs/thesis.md) en el repositorio de Kubeport.

## Despliegue para evaluación (Docker Compose)

Si el objetivo es **probar la aplicación**, no editarla, ir directamente a [`deploy/`](deploy/).
Ese directorio contiene un *stack* Docker Compose autocontenido que levanta:

- MariaDB + Redis (caché y cola).
- Un bench Frappe v16 con Kubeport y Helm 3 ya instalados.
- Un clúster Kubernetes embebido (k3s, un solo nodo) que Kubeport gestiona desde el primer arranque.

Tres comandos:

```bash
cd deploy
docker compose build kubeport       # ~5–10 min la primera vez
docker compose up -d                # ~2 min de first-run init
open http://localhost:8000          # Administrator / admin
```

Ver [`deploy/README.md`](deploy/README.md) para el recorrido de evaluación
guiado (registrar un repo Helm, desplegar una release, crear un sitio Frappe,
programar *backups*).

## DEVELOPMENT SETUP

This project supports a devcontainer-first workflow.

- Keep the host minimal: `docker`, `docker compose`, `k3d`, `code`
- Run Kubernetes and Helm tooling inside the dev container: `kubectl`, `helm`
- Avoid manual binary installs on the host unless you have a separate admin need

### Host prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running
- Docker Compose v2 available through `docker compose`
- [Visual Studio Code](https://code.visualstudio.com/)
- [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension
- [k3d](https://k3d.io/) installed on the host

Recommended validation:

```bash
docker --version
docker compose version
k3d version
code --version
```

If Docker requires `sudo`, fix that before continuing. The normal developer flow should not rely on root shells.

### Where commands should run

| Command family | Run on host | Run in dev container |
| --- | --- | --- |
| `docker`, `docker compose`, `k3d`, `code` | Yes | No |
| `bench`, `python`, `kubectl`, `helm` | No | Yes |

### Setup steps

1. Copy `devcontainer-example` to `.devcontainer` only if `.devcontainer/` does not already exist:

   ```bash
   cp -R devcontainer-example .devcontainer
   ```

2. Copy the VS Code development settings if `development/.vscode` does not already exist:

   ```bash
   cp -R development/vscode-example development/.vscode
   ```

3. Open this repository in VS Code.

4. Reopen the workspace in the dev container.
   - `Ctrl + Shift + P`
   - `Dev Containers: Reopen in Container`

5. Let the dev container finish provisioning. The active `.devcontainer/devcontainer.json` installs Kubernetes and Helm tooling through the official combined feature:
   - `ghcr.io/devcontainers/features/kubectl-helm-minikube:1`
   - usable binaries include `kubectl` and `helm`

6. Inside the dev container, run the bootstrap script:

   ```bash
   cd /workspace/development
   python installer.py
   ```

7. Start the bench inside the dev container:

   ```bash
   cd /workspace/development/frappe-bench
   bench start
   ```

### Manual bench commands

If you want to create the bench manually instead of using `installer.py`, run these commands inside the dev container:

```bash
bench init --python 3.13 --node 20 --apps-path apps-example.json --frappe-path https://github.com/frappe/frappe --frappe-branch version-16 <BENCH_NAME>
bench new-site <SITE_NAME>.localhost --mariadb-root-password 123 --admin-password admin
```

### Verification inside the dev container

After the container opens, verify the required binaries:

```bash
kubectl version --client
helm version
python --version
bench --version
```

### Access the app

- URL: [http://<SITE_NAME>.localhost:8000](http://<SITE_NAME>.localhost:8000)
- User: `Administrator`
- Password: the admin password used when creating the site

### Notes on security

- The supported setup keeps `kubectl` and `helm` inside the dev container.
- Public Dev Container features from `ghcr.io/devcontainers/features/...` do not require manual credentials in the normal case.
- The SSH home directory is mounted read-only into the container.
- Prefer least-privilege kubeconfigs for development clusters.
- Treat old manual `curl` install snippets as troubleshooting-only, not the primary setup path.

## TODO

### HIGH

- [ ] Despliegue de ERPNext a traves de Helm Chart
- [x] Crear DocType que permite conectar a un cluster de Kubernetes
- [x] Crear un manifiesto y cargarlo
- [x] Poder ejecutar comandos desde la interfaz de Frappe (`kubectl`)
- [x] K3d
  - [x] Crear cluster de K3d
  - [x] Conectar a cluster de K3d
  - [x] Ejecutar comandos en el cluster de K3d

## Resources

- [Frappe framework](https://github.com/frappe/frappe)
- [ERPNext](https://github.com/frappe/erpnext)
- [Frappe Bench](https://github.com/frappe/bench)
- [Dev Container guide](docs/05-development/01-development.md)
- [DEV_CONTAINER.md](DEV_CONTAINER.md)

## License

Este proyecto esta licenciado bajo MIT. Ver [LICENSE](LICENSE).
