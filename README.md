# CONTROL PLANE FRAPPE K8S

## DEVELOPMENT SETUP

> Es recomendable tener la extensión Dev Container instalada. De esta manera, VSCode detecta automáticamente los contenedores de desarrollo.

Para configurar el entorno de desarrollo, sigue los siguientes pasos:

1. Renombra devcontainer-example a .devcontainer.
2. Reabrir el proyecto en el contenedor de desarrollo.
  - Si tienes la extensión, aparecerá una notificación automáticamente.
  - Si no tienes la extensión, pulsa CTRL + SHIFT + P > Dev Containers: Reopen in Container.

Con ello, se creará un entorno de desarrollo consistente y fácil de usar.

> [!NOTE]
> La primera vez que se ejecute, tardará unos minutos.

## TODO

- [ ] Despliegue de ERPNext a través de Helm Chart
- [ ] Crear DocType que permite conectar a un clúster de Kubernetes.
- [ ] Crear un manifiesto y cargarlo.
- [ ] Poder ejecutar comandos desde la interfaz de Frappe (kubectl).
- [ ] K3d:
  - [ ] Crear clúster de K3d
  - [ ] Conectar a clúster de K3d
  - [ ] Ejecutar comandos en el clúster de K3d


## Documentation Links

### [Getting Started Guide](docs/getting-started.md)

### [Frequently Asked Questions](https://github.com/frappe/frappe_docker/wiki/Frequently-Asked-Questions)

### [Getting Started](#getting-started)

### [Deployment Methods](docs/01-getting-started/01-choosing-a-deployment-method.md)

### [Container Setup Overview](docs/02-setup/01-overview.md)

### [Development](docs/05-development/01-development.md)

## Resources

- [Frappe framework](https://github.com/frappe/frappe),
- [ERPNext](https://github.com/frappe/erpnext),
- [Frappe Bench](https://github.com/frappe/bench).

## License

Este proyecto está licenciado bajo la Licencia MIT al igual que el resto de los proyectos de Frappe. Ver [LICENSE](LICENSE) para más detalles.