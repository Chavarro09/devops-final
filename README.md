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
hostname                            # taller-utp
pwd                                 # /home/estudiante22
ls -la
docker --version && docker compose version
free -h && df -h /                  # memoria y disco disponibles en el servidor compartido
mkdir -p ~/estudiante22             # mi carpeta de trabajo (no existía)
cd ~/estudiante22
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
# Ajustar estudiante y puerto, y generar una contraseña aleatoria que nunca se muestra en pantalla
sed -i "s/^ESTUDIANTE=.*/ESTUDIANTE=estudiante22/; s/^API_PORT=.*/API_PORT=8022/" .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" .env
grep -v PASSWORD .env               # revisar (DB_HOST=db y DB_PORT=5432 quedan igual)
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

### 9. Corregir vulnerabilidades y volver a desplegar

Con los hallazgos de Trivy se corrigieron el `Dockerfile` y `app/requirements.txt` en mi equipo (ver [Resultados](#resultados-devsecops)), se subieron con commits y en el servidor:

```bash
mkdir -p reportes/inicial           # se guarda el primer reporte para comparar
cp reportes/trivy.txt reportes/inicial/trivy-inicial.txt
cp reportes/resumen.txt reportes/inicial/resumen-inicial.txt
git pull                            # trae los cambios del Dockerfile
docker compose up -d --build        # reconstruye solo la API; la BD y sus datos siguen intactos
curl http://localhost:8022/tareas   # la tarea creada antes sigue ahí (volumen persistente)
./seguridad.sh                      # nuevo análisis
```

### 10. Subir la evidencia a GitHub

Para no guardar un token de GitHub en el servidor compartido, la evidencia se copia a mi equipo con `scp` y se sube desde allí:

```bash
# en mi equipo, dentro de devops-final/
scp -r estudiante22@178.128.14.98:estudiante22/devops-final/reportes .
scp estudiante22@178.128.14.98:estudiante22/devops-final/monitoreo.log .
grep -ri password reportes/ monitoreo.log   # comprobar que no hay credenciales
git add reportes/ monitoreo.log README.md
git commit -m "Agrega reportes de seguridad, registro de monitoreo y resultados"
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

### Resultados DevSecOps

Ejecución en el servidor el 2026-11-18 (UTC). El primer análisis quedó guardado en `reportes/inicial/`.

| Herramienta | Primer análisis | Después de corregir |
|---|---|---|
| Gitleaks | 0 secretos | 0 secretos (12 commits revisados) |
| Semgrep | 0 hallazgos | 0 hallazgos (164 reglas sobre `app.py`, `Dockerfile` y `docker-compose.yml`) |
| Syft | falló (ver abajo) | 119 componentes en el SBOM |
| Trivy | 227 CVE (HIGH 48 · MEDIUM 98 · LOW 67 · UNKNOWN 14) — **9 con parche disponible** | 221 CVE (HIGH 48 · MEDIUM 93 · LOW 66 · UNKNOWN 14) — **0 con parche aplicable** |
| Hadolint | 0 observaciones | 0 observaciones |

**Correcciones aplicadas a partir de Trivy:**

| Paquete | Antes | Después | CVE corregidas |
|---|---|---|---|
| `zlib1g` (Debian) | 1.3.1-1+b1 | 1.3.1-1+deb13u1 | CVE-2026-85091 (HIGH), CVE-2026-27171 — `apt-get upgrade` en el Dockerfile |
| `pip` | 25.0.1 | 26.3 | CVE-2025-8869, CVE-2026-13346, CVE-2026-3219, CVE-2026-6357, CVE-2026-8643, CVE-2026-1703 |
| `Flask` | 3.0.3 | 3.1.3 | CVE-2026-27205 |
| `setuptools` | — | 84.1.0 | CVE-2025-47273 (HIGH) y otras |

**Lo que queda:**
- **218 CVE del sistema base** (Debian 13, `python:3.12-slim`): Debian todavía no ha publicado parche para ninguna, así que no hay versión a la cual actualizar. Se corrigen solas al reconstruir la imagen cuando salgan los parches (`docker compose build --pull`).
- **3 CVE de "setuptools 70.3.0"**: no es un setuptools instalado (el instalado es el 84.1.0). Es la copia interna de `pkg_resources` que pip 26.3 declara en su propio SBOM (`pip/_vendor/bom.cdx.json`). Trivy la cuenta como paquete, pero no se puede actualizar por separado. Se dejó documentado en vez de ocultarlo con `.trivyignore`.

**Problemas del script encontrados en la primera ejecución y corregidos:**
- **Syft falló** con `mkdir /tmp/stereoscope-…: permission denied`, porque su imagen no deja escribir en `/tmp` a un usuario sin privilegios. Se le monta una carpeta temporal del host.
- **Mensajes de descarga en los reportes:** los "Pulling…" de Docker quedaban dentro de los reportes. Ahora las imágenes se descargan antes, en silencio, y Gitleaks se ejecuta con `--no-color`.

## Monitoreo (función `monitorear`)

```bash
./seguridad.sh monitorear
```

1. Consulta `http://localhost:8022/health` y evalúa el código HTTP (200 = OK).
2. Muestra el estado de los contenedores `est22_*` (`docker ps -a --filter name=^est22_`).
3. Muestra los últimos logs de `est22_api` y `est22_db`.
4. Agrega una línea con fecha a `monitoreo.log`. Registro real del servidor:

```
[2026-11-18 02:20:40] estado=OK http=200 url=http://localhost:8022/health respuesta={"base_de_datos":"conectada","estado":"ok"} contenedores=est22_api=Up 30 seconds (healthy);est22_db=Up 6 minutes (healthy)
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
