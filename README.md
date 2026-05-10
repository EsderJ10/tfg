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

> Es recomendable tener la extensión Dev Container instalada. De esta manera, VSCode detecta automáticamente los contenedores de desarrollo.

### Requisitos previos

- [Docker](https://docs.docker.com/get-docker/) instalado y en funcionamiento.
- [Visual Studio Code](https://code.visualstudio.com/) con la extensión [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) instalada.

### Pasos para configurar el entorno

1. Copiar `devcontainer-example` a `.devcontainer`:

   ```bash
   cp -R devcontainer-example .devcontainer
   ```

2. Copiar la configuración de VSCode para el contenedor de desarrollo:

   ```bash
   cp -R development/vscode-example development/.vscode
   ```

3. Reabrir el proyecto en el contenedor de desarrollo.
   - Si tienes la extensión, aparecerá una notificación automáticamente.
   - Si no tienes la extensión, pulsa `CTRL + SHIFT + P` > `Dev Containers: Reopen in Container`.

> [!NOTE]
> La primera vez que se ejecute, tardará unos minutos en descargar las imágenes y configurar el entorno.

### Inicializar Bench y crear un sitio

Una vez dentro del contenedor, ejecuta el instalador automático:

```bash
python installer.py
```

Esto creará un bench con Frappe e instalará las apps definidas en `apps-example.json`.

Para más opciones:

```bash
python installer.py --help
```

O puedes hacerlo manualmente siguiendo la [guía de desarrollo](docs/05-development/01-development.md).

Algunos de los comandos que puedes usar son:

```bash
bench init --python 3.13 --node 20 --apps-path apps-example.json --frappe-path https://github.com/frappe/frappe --frappe-branch version-16 <NOMBRE_DEL_BENCH>
```

Para crear un sitio:

```bash
bench new-site <NOMBRE_DEL_SITIO>.localhost --mariadb-root-password [PASSWORD] --admin-password admin
```

### Acceder a la aplicación

- URL: [<NOMBRE_DEL_SITIO>.localhost:8000](http://<NOMBRE_DEL_SITIO>.localhost:8000)
- Usuario: `Administrator`
- Contraseña: `CONTRASEÑA_DEL_ADMINISTRADOR`

## TODO

### HIGH

- [ ] Despliegue de ERPNext a través de Helm Chart
- [ ] Crear DocType que permite conectar a un clúster de Kubernetes.
- [ ] Crear un manifiesto y cargarlo.
- [ ] Poder ejecutar comandos desde la interfaz de Frappe (kubectl).
- [ ] K3d:
  - [ ] Crear clúster de K3d
  - [ ] Conectar a clúster de K3d
  - [ ] Ejecutar comandos en el clúster de K3d

## Resources

- [Frappe framework](https://github.com/frappe/frappe)
- [ERPNext](https://github.com/frappe/erpnext)
- [Frappe Bench](https://github.com/frappe/bench)
- [Guía de desarrollo con Dev Containers](docs/05-development/01-development.md)

## License

Este proyecto está licenciado bajo la Licencia MIT al igual que el resto de los proyectos de Frappe. Ver [LICENSE](LICENSE) para más detalles.