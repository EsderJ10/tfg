# CONTROL PLANE FRAPPE K8S

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
- [x] Crear DocType que permite conectar a un clúster de Kubernetes.
   - [x] Modificar el indexado. Utilzar nombre en cambio de id autogenerado.
- [x] Crear un manifiesto y cargarlo.
- [x] Poder ejecutar comandos desde la interfaz de Frappe (kubectl).
- [x] K3d:  
  - [x] Crear clúster de K3d
  - [x] Conectar a clúster de K3d
  - [x] Ejecutar comandos en el clúster de K3d

## Resources

- [Frappe framework](https://github.com/frappe/frappe)
- [ERPNext](https://github.com/frappe/erpnext)
- [Frappe Bench](https://github.com/frappe/bench)
- [Guía de desarrollo con Dev Containers](docs/05-development/01-development.md)

## License

Este proyecto está licenciado bajo la Licencia MIT al igual que el resto de los proyectos de Frappe. Ver [LICENSE](LICENSE) para más detalles.