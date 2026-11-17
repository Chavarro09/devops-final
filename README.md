# Proyecto final DevOps — API de tareas (estudiante22)

API REST de tareas escrita en Python (Flask + Gunicorn) con base de datos PostgreSQL, desplegada con **Docker Compose** en el servidor de clase. El proyecto aplica **Git/GitHub**, **comandos Linux**, **Docker**, **DevSecOps** (Gitleaks, Semgrep, Syft, Trivy y Hadolint) y **monitoreo**.

| Dato | Valor |
|---|---|
| Estudiante | Andrés Camilo Quintero Chavarro — `estudiante22` |
| Servidor | `178.128.14.98` |
| Puerto de la API | `8022` (8000 + 22) |
| Contenedores | `est22_db`, `est22_api` |
| API en producción | http://178.128.14.98:8022/health |
| Repositorio base | https://github.com/jsansis-utp/devops-final |

## Arquitectura

```
 Internet ──► 178.128.14.98:8022
                    │
                    ▼   (proyecto Compose "estudiante22", red "backend")
       ┌────────────────────────┐   db:5432    ┌────────────────────────┐
       │ est22_api              │ ───────────► │ est22_db               │
       │ Flask + Gunicorn       │   (interna)  │ PostgreSQL 16          │
       │ puerto interno 5000    │              │ sin puertos publicados │
       └────────────────────────┘              └───────────┬────────────┘
                                                           │
                                               volumen estudiante22_db_data
```

- La **base de datos no se publica**: el servicio `db` no tiene sección `ports`. La API la alcanza por el nombre del servicio (`db`) y el puerto interno `5432` a través de la red de Docker. Por eso no se usa el puerto `5454` asignado para PostgreSQL.
- Los datos persisten en el volumen `estudiante22_db_data`, aunque se recreen los contenedores.
- La primera línea del `docker-compose.yml` es `name: estudiante22`, para que el proyecto, la red y el volumen no choquen con los de los demás estudiantes del servidor compartido.
- La API espera a que PostgreSQL esté sano (`depends_on: condition: service_healthy`, con `pg_isready`) y corre como usuario sin privilegios (`appuser`).

## Estructura del repositorio

| Archivo | Descripción |
|---|---|
| `app/app.py` | API de tareas (Flask). Escribe un log JSON por cada petición. |
| `app/requirements.txt` | Dependencias de Python. |
| `Dockerfile` | Imagen de la API (`python:3.12-slim`, usuario sin privilegios, HEALTHCHECK). |
| `docker-compose.yml` | Servicios `db` (PostgreSQL) y `api`, volumen y red. |
| `.env.example` | Plantilla de variables. Se copia como `.env` (que **no** se sube). |
| `seguridad.sh` | Análisis DevSecOps (5 herramientas) y función `monitorear`. |
| `reportes/` | Resultados de los análisis de seguridad (evidencia). |
| `monitoreo.log` | Historial con fecha de las verificaciones de monitoreo (evidencia). |

## Endpoints

| Método | Ruta | Uso |
|---|---|---|
| GET | `/` | Información del servicio y del estudiante |
| GET | `/health` | Estado de la API y de la conexión a la base de datos |
| GET | `/tareas` | Lista las tareas |
| POST | `/tareas` | Crea una tarea: `{"titulo": "..."}` |
| PUT | `/tareas/<id>` | Actualiza: `{"titulo": "...", "completada": true}` |
| DELETE | `/tareas/<id>` | Elimina una tarea |

```bash
curl http://178.128.14.98:8022/health
curl -X POST http://178.128.14.98:8022/tareas -H "Content-Type: application/json" -d '{"titulo":"Primera tarea"}'
curl http://178.128.14.98:8022/tareas
curl -X PUT http://178.128.14.98:8022/tareas/1 -H "Content-Type: application/json" -d '{"completada":true}'
curl -X DELETE http://178.128.14.98:8022/tareas/1
```

## Comandos Linux usados, en orden

### 1. En mi equipo: clave SSH y repositorio

```bash
# Crear el par de claves SSH (ed25519) para entrar al servidor
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "camilochavarro-devops-utp"
ls -la ~/.ssh                       # id_ed25519 (privada, 600) e id_ed25519.pub (pública)
cat ~/.ssh/id_ed25519.pub           # esta línea se entregó al profesor para habilitar el acceso

# Fork del repositorio base en GitHub (equivalente al botón "Fork") y clon local
gh repo fork jsansis-utp/devops-final --clone=false
git clone https://github.com/Chavarro09/devops-final.git
cd devops-final

# Crear los archivos del proyecto, dar permiso de ejecución al script y versionar
nano docker-compose.yml
nano seguridad.sh
chmod +x seguridad.sh
nano README.md
git add docker-compose.yml && git commit -m "Agrega docker-compose.yml con servicios db y api"
git add seguridad.sh       && git commit -m "Agrega seguridad.sh con análisis DevSecOps y monitoreo"
git add .gitignore         && git commit -m "Permite versionar reportes/ y monitoreo.log como evidencia"
git add README.md          && git commit -m "Agrega README con documentación y comandos del proyecto"
git push origin main
```

### 2. Conexión al servidor y navegación

```bash
ssh estudiante22@178.128.14.98      # entra con la clave ~/.ssh/id_ed25519
whoami                              # estudiante22
pwd                                 # /home/estudiante22
ls -la
cd ~/estudiante22                   # mi carpeta de trabajo en el droplet
```

### 3. Clonar mi fork en el servidor

```bash
git clone https://github.com/Chavarro09/devops-final.git
cd devops-final
ls -la
git log --oneline --graph
```

### 4. Variables de entorno (archivo `.env`, nunca se sube)

```bash
cp .env.example .env
nano .env                           # ESTUDIANTE=estudiante22, API_PORT=8022, POSTGRES_PASSWORD=<clave segura>, DB_HOST=db, DB_PORT=5432
chmod 600 .env                      # solo mi usuario puede leer las credenciales
ls -l .env
git status                          # .env NO aparece: está en .gitignore
chmod +x seguridad.sh               # permiso de ejecución del script
```

### 5. Revisión previa en el servidor compartido

```bash
docker ps -a | grep est22           # contenedores viejos con mi prefijo
docker stop est22_db est22_api      # solo si existían de ejercicios anteriores
docker rm est22_db est22_api
docker compose config               # valida el docker-compose.yml con las variables del .env
```

### 6. Despliegue

```bash
docker compose up -d --build        # construye la imagen est22_api:1.0 y levanta db y api
docker compose ps                   # ambos servicios "running"; db "healthy"
docker compose ls                   # proyecto "estudiante22"
docker volume ls | grep estudiante22
docker network ls | grep estudiante22
```

### 7. Verificación

```bash
curl http://localhost:8022/health   # {"base_de_datos":"conectada","estado":"ok"}
curl http://178.128.14.98:8022/health
curl -X POST http://localhost:8022/tareas -H "Content-Type: application/json" -d '{"titulo":"Primera tarea"}'
curl http://localhost:8022/tareas
docker logs --tail 20 est22_api     # log JSON de cada petición
```

### 8. DevSecOps y monitoreo

```bash
./seguridad.sh                      # 5 análisis -> reportes/  y monitoreo -> monitoreo.log
ls -la reportes/
cat reportes/resumen.txt
./seguridad.sh monitorear           # solo monitoreo
tail monitoreo.log
```

### 9. Subir la evidencia a GitHub

```bash
git add reportes/ monitoreo.log
git commit -m "Agrega reportes de seguridad y registro de monitoreo"
git push origin main
git log --oneline --graph
```

### Operación del día a día

```bash
docker compose logs -f api          # seguir los logs de la API
docker compose restart api          # reiniciar solo la API
docker compose down                 # detener (los datos siguen en el volumen)
git pull && docker compose up -d --build   # actualizar después de un cambio
```

## Docker

`docker-compose.yml` define:

- **`db`** — `postgres:16-alpine`, contenedor `est22_db`, credenciales tomadas del `.env`, volumen `db_data:/var/lib/postgresql/data`, **sin `ports`**, healthcheck con `pg_isready` y `restart: unless-stopped`.
- **`api`** — construida con el `Dockerfile` (imagen `est22_api:1.0`), contenedor `est22_api`, variables por `env_file: .env`, publicada en `8022:5000`, arranca después de que `db` esté sana.
- Red `backend` y volumen `db_data`. Con `name: estudiante22` quedan como `estudiante22_backend` y `estudiante22_db_data`.

## DevSecOps (`seguridad.sh`)

Las herramientas se ejecutan con sus **imágenes Docker oficiales**, con versión fija, así que no hay que instalar nada en el servidor. Los contenedores corren con mi UID, de modo que los reportes quedan a mi nombre.

| # | Herramienta | Qué revisa | Reporte |
|---|---|---|---|
| 1 | **Gitleaks** | Secretos (claves, tokens, contraseñas) en el historial de Git | `reportes/gitleaks.json` |
| 2 | **Semgrep** | Análisis estático (SAST) de Python, Dockerfile y docker-compose | `reportes/semgrep.txt`, `semgrep.json` |
| 3 | **Syft** | Inventario de dependencias (SBOM) de la imagen `est22_api:1.0` | `reportes/syft-sbom.txt`, `syft-sbom.cdx.json` (CycloneDX) |
| 4 | **Trivy** | Vulnerabilidades (CVE) de la imagen | `reportes/trivy.txt`, `trivy.json` |
| 5 | **Hadolint** | Buenas prácticas del `Dockerfile` | `reportes/hadolint.txt` |

Al final se genera `reportes/resumen.txt` con el conteo de hallazgos de cada herramienta.

```bash
./seguridad.sh             # análisis + monitoreo
./seguridad.sh escanear    # solo análisis
```

## Monitoreo (función `monitorear`)

```bash
./seguridad.sh monitorear
```

1. Consulta `http://localhost:8022/health` y evalúa el código HTTP (200 = OK).
2. Muestra el estado de los contenedores `est22_*` (`docker ps -a --filter name=^est22_`).
3. Muestra los últimos logs de `est22_api` y `est22_db`.
4. Agrega una línea con fecha a `monitoreo.log`, por ejemplo:

```
[2026-11-17 21:00:00] estado=OK http=200 url=http://localhost:8022/health respuesta={"base_de_datos":"conectada","estado":"ok"} contenedores=est22_api=Up 5 minutes (healthy);est22_db=Up 5 minutes (healthy)
```

El script termina con código `0` si la API está bien y `1` si falla, así que también sirve para automatizarlo con cron, por ejemplo cada 5 minutos:

```bash
crontab -e
*/5 * * * * cd ~/estudiante22/devops-final && ./seguridad.sh monitorear >/dev/null 2>&1
```

## Seguridad

- El archivo `.env` está en `.gitignore` y `.dockerignore`, y tiene permisos `600`. Ninguna contraseña está en el repositorio; Gitleaks lo verifica.
- PostgreSQL no se expone a Internet.
- La API corre como usuario sin privilegios dentro del contenedor.
- Las versiones de las imágenes y dependencias están fijadas.
- Solo se tocan los contenedores con prefijo `est22_`.

## Historial de commits

```bash
git log --oneline --graph
```
