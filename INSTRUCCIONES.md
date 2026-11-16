# Proyecto final DevOps

Cada estudiante despliega en su carpeta `estudianteXX` del droplet esta API de tareas junto con una base de datos PostgreSQL, usando Docker, y entrega evidencias de Git, Linux, Docker, DevSecOps y monitoreo.

- **Servidor:** `178.128.14.98` (acceso por SSH con su usuario).
- **Su puerto:** `8000 + XX`. Ejemplo: estudiante07 usa el `8007`; estudiante23 usa el `8023`.

## Qué contiene este repositorio

| Archivo | Descripción |
|---|---|
| `app/app.py` | API de tareas en Python (Flask). No necesita modificarla. |
| `app/requirements.txt` | Dependencias de la API. |
| `Dockerfile` | Construye la imagen de la API. Dentro del contenedor escucha en el puerto `5000`. |
| `.env.example` | Plantilla de variables de entorno. Cópiela como `.env` y ajústela. |
| `.gitignore` | Evita subir `.env`, reportes y logs. |

## Endpoints de la API

| Método | Ruta | Uso |
|---|---|---|
| GET | `/` | Información del servicio y del estudiante |
| GET | `/health` | Estado de la API y de la conexión a la base de datos |
| GET | `/tareas` | Lista las tareas |
| POST | `/tareas` | Crea una tarea: `{"titulo": "..."}` |
| PUT | `/tareas/<id>` | Actualiza: `{"titulo": "...", "completada": true}` |
| DELETE | `/tareas/<id>` | Elimina una tarea |

Ejemplos (cambie `80XX` por su puerto):

```bash
curl http://178.128.14.98:80XX/health
curl -X POST http://178.128.14.98:80XX/tareas -H "Content-Type: application/json" -d '{"titulo":"Primera tarea"}'
curl http://178.128.14.98:80XX/tareas
```

La API escribe un log en formato JSON por cada petición; se consulta con `docker logs`.

## Lo que usted debe construir

**1. Git y GitHub.** Haga *fork* de este repositorio en su cuenta de GitHub, clónelo dentro de su carpeta en el droplet y trabaje con commits propios que muestren su avance. Escriba un `README.md` que explique qué hace el proyecto y cómo ponerlo en marcha. Entregue el historial con `git log --oneline --graph`.

**2. Linux.** En el `README.md`, documente en orden todos los comandos que usó para poner en marcha el proyecto: conexión por SSH, navegación, creación de archivos y carpetas, permisos, despliegue y verificación.

**3. Docker.** Cree un `docker-compose.yml` con dos servicios:
- `db`: PostgreSQL, con un volumen para persistir los datos y sin publicar su puerto hacia afuera.
- `api`: construida con el `Dockerfile` de este repositorio, publicada en su puerto (`80XX:5000`) y con las variables del archivo `.env`.

**4. DevSecOps.** Cree un script `seguridad.sh` que ejecute y guarde sus resultados en la carpeta `reportes/`:
- **Gitleaks:** búsqueda de secretos en el repositorio.
- **Semgrep:** análisis estático del código.
- **Syft:** inventario de dependencias (SBOM) de la imagen.
- **Trivy:** vulnerabilidades de la imagen.
- **Hadolint:** buenas prácticas del `Dockerfile`.

Las herramientas pueden ejecutarse instaladas o mediante sus imágenes Docker oficiales.

**5. Monitoreo.** En el mismo script, una función `monitorear` que verifique si la API responde (`/health`), muestre el estado de los contenedores y los últimos registros de log, y deje constancia con fecha en `monitoreo.log`.

## Entrega

1. Enlace a su repositorio en GitHub con: `README.md`, historial de commits, `docker-compose.yml`, `seguridad.sh` y la carpeta `reportes/` (súbala como evidencia aunque esté en `.gitignore`, o adjúntela aparte).
2. La API funcionando en `http://178.128.14.98:80XX`.

**Importante:** nunca suba el archivo `.env` ni contraseñas al repositorio. Gitleaks lo detectará.
