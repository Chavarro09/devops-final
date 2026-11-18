#!/usr/bin/env bash
# =============================================================================
# seguridad.sh - DevSecOps y monitoreo del proyecto final (estudiante22)
#
# Uso:
#   ./seguridad.sh              Ejecuta los 5 análisis de seguridad y luego monitorea
#   ./seguridad.sh escanear     Solo los análisis de seguridad
#   ./seguridad.sh monitorear   Solo el monitoreo de la API y los contenedores
#
# Las herramientas se ejecutan con sus imágenes Docker oficiales, así que no
# hace falta instalarlas en el servidor. Los resultados quedan en reportes/.
# =============================================================================
set -uo pipefail

# ----------------------------------------------------------- configuración
ESTUDIANTE="estudiante22"
PREFIJO="est22"
PUERTO="8022"
IMAGEN_API="est22_api:1.0"
URL_HEALTH="http://localhost:${PUERTO}/health"

# Versiones fijas de las herramientas (evita sorpresas con :latest)
IMG_GITLEAKS="zricethezav/gitleaks:v8.21.2"
IMG_SEMGREP="semgrep/semgrep:1.100.0"
IMG_SYFT="anchore/syft:v1.18.1"
IMG_TRIVY="aquasec/trivy:0.69.3"
IMG_HADOLINT="hadolint/hadolint:v2.12.0"

DIR_PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR_REPORTES="${DIR_PROYECTO}/reportes"
LOG_MONITOREO="${DIR_PROYECTO}/monitoreo.log"
SOCKET_DOCKER="/var/run/docker.sock"

# Los contenedores corren con nuestro UID para que los reportes queden a
# nuestro nombre y no como root.
USUARIO="$(id -u):$(id -g)"

# ---------------------------------------------------------------- utilidades
fecha() { date '+%Y-%m-%d %H:%M:%S'; }
info()  { echo -e "\n\033[1;34m[$(fecha)] $*\033[0m"; }
ok()    { echo -e "\033[1;32m  ✔ $*\033[0m"; }
falla() { echo -e "\033[1;31m  ✘ $*\033[0m"; }

# Descarga en silencio las imágenes de las herramientas, para que los mensajes
# de "Pulling..." no se mezclen con los reportes
descargar_herramientas() {
    info "Preparando imágenes de las herramientas"
    local img
    for img in "$IMG_GITLEAKS" "$IMG_SEMGREP" "$IMG_SYFT" "$IMG_TRIVY" "$IMG_HADOLINT"; do
        docker image inspect "$img" >/dev/null 2>&1 || docker pull -q "$img" >/dev/null
    done
}

# Si una herramienta no encontró nada, el reporte lo dice en vez de quedar vacío
sin_hallazgos() {
    [ -s "$1" ] || echo "$2" > "$1"
}

# Comprueba que la imagen de la API exista (Syft y Trivy la necesitan)
asegurar_imagen() {
    if ! docker image inspect "$IMAGEN_API" >/dev/null 2>&1; then
        info "La imagen $IMAGEN_API no existe; construyéndola con docker compose"
        (cd "$DIR_PROYECTO" && docker compose build api)
    fi
}

# --------------------------------------------------------- 1. Gitleaks
escanear_secretos() {
    info "1/5 Gitleaks: búsqueda de secretos en el historial de Git"
    docker run --rm -u "$USUARIO" \
        -v "${DIR_PROYECTO}:/repo" \
        "$IMG_GITLEAKS" detect --source /repo --no-banner \
        --report-format json --report-path /repo/reportes/gitleaks.json \
        --exit-code 0 > "${DIR_REPORTES}/gitleaks.txt" 2>&1 \
        && ok "reportes/gitleaks.json" || falla "Gitleaks terminó con errores"
}

# ----------------------------------------------------------- 2. Semgrep
analisis_estatico() {
    info "2/5 Semgrep: análisis estático del código (SAST)"
    docker run --rm -u "$USUARIO" -e HOME=/tmp \
        -v "${DIR_PROYECTO}:/src" -w /src \
        "$IMG_SEMGREP" semgrep scan \
        --config p/python --config p/dockerfile --config p/docker-compose \
        --metrics off --exclude reportes \
        --text-output /src/reportes/semgrep.txt \
        --json-output /src/reportes/semgrep.json \
        > /dev/null 2>"${DIR_REPORTES}/semgrep.log" \
        && ok "reportes/semgrep.txt y semgrep.json" || falla "Semgrep terminó con errores (ver reportes/semgrep.log)"
    sin_hallazgos "${DIR_REPORTES}/semgrep.txt" \
        "Semgrep: 0 hallazgos (reglas p/python, p/dockerfile y p/docker-compose). Detalle en semgrep.log y semgrep.json."
}

# -------------------------------------------------------------- 3. Syft
generar_sbom() {
    info "3/5 Syft: inventario de dependencias (SBOM) de $IMAGEN_API"
    # La imagen de Syft no permite escribir en /tmp a un usuario sin
    # privilegios: se le monta una carpeta temporal propia.
    local tmp
    tmp="$(mktemp -d)"
    docker run --rm -u "$USUARIO" -e HOME=/tmp -e TMPDIR=/tmp \
        --group-add "$(stat -c '%g' "$SOCKET_DOCKER")" \
        -v "${SOCKET_DOCKER}:/var/run/docker.sock" \
        -v "${tmp}:/tmp" \
        -v "${DIR_REPORTES}:/out" \
        "$IMG_SYFT" "docker:${IMAGEN_API}" -q \
        -o table=/out/syft-sbom.txt \
        -o cyclonedx-json=/out/syft-sbom.cdx.json \
        2> "${DIR_REPORTES}/syft.log" \
        && ok "reportes/syft-sbom.txt y syft-sbom.cdx.json" || falla "Syft terminó con errores (ver reportes/syft.log)"
    rm -rf "$tmp"
    [ -s "${DIR_REPORTES}/syft.log" ] || rm -f "${DIR_REPORTES}/syft.log"
}

# ------------------------------------------------------------- 4. Trivy
escanear_vulnerabilidades() {
    info "4/5 Trivy: vulnerabilidades de la imagen $IMAGEN_API"
    mkdir -p "${HOME}/.cache/trivy"
    local comun=(docker run --rm -u "$USUARIO" -e HOME=/tmp
        --group-add "$(stat -c '%g' "$SOCKET_DOCKER")"
        -v "${SOCKET_DOCKER}:/var/run/docker.sock"
        -v "${HOME}/.cache/trivy:/cache"
        -v "${DIR_REPORTES}:/out"
        "$IMG_TRIVY" image --cache-dir /cache --quiet --scanners vuln)
    "${comun[@]}" --format table --output /out/trivy.txt "$IMAGEN_API" \
        && "${comun[@]}" --skip-db-update --format json --output /out/trivy.json "$IMAGEN_API" \
        && ok "reportes/trivy.txt y trivy.json" || falla "Trivy terminó con errores"
}

# ---------------------------------------------------------- 5. Hadolint
revisar_dockerfile() {
    info "5/5 Hadolint: buenas prácticas del Dockerfile"
    docker run --rm -i "$IMG_HADOLINT" hadolint --no-fail - \
        < "${DIR_PROYECTO}/Dockerfile" > "${DIR_REPORTES}/hadolint.txt" 2>&1 \
        && ok "reportes/hadolint.txt" || falla "Hadolint terminó con errores"
    sin_hallazgos "${DIR_REPORTES}/hadolint.txt" \
        "Hadolint: 0 observaciones. El Dockerfile cumple las reglas de Hadolint."
}

# Ejecuta los cinco análisis y deja un resumen
escanear() {
    mkdir -p "$DIR_REPORTES"
    descargar_herramientas
    asegurar_imagen
    escanear_secretos
    analisis_estatico
    generar_sbom
    escanear_vulnerabilidades
    revisar_dockerfile

    {
        echo "Resumen DevSecOps - ${ESTUDIANTE} - $(fecha)"
        echo "Imagen analizada: ${IMAGEN_API}"
        echo
        if command -v python3 >/dev/null; then
            python3 - "$DIR_REPORTES" <<'PY'
import json, os, sys
d = sys.argv[1]
def cargar(nombre):
    try:
        with open(os.path.join(d, nombre)) as f:
            return json.load(f)
    except Exception:
        return None
g = cargar("gitleaks.json")
print(f"Gitleaks : {len(g) if isinstance(g, list) else '?'} secretos encontrados")
s = cargar("semgrep.json")
print(f"Semgrep  : {len(s['results']) if s else '?'} hallazgos")
sb = cargar("syft-sbom.cdx.json")
print(f"Syft     : {len(sb.get('components', [])) if sb else '?'} componentes en el SBOM")
t = cargar("trivy.json")
if t:
    sev = {}
    for r in t.get("Results", []):
        for v in r.get("Vulnerabilities") or []:
            sev[v["Severity"]] = sev.get(v["Severity"], 0) + 1
    orden = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]
    print("Trivy    : " + ", ".join(f"{k}={sev.get(k, 0)}" for k in orden))
else:
    print("Trivy    : ?")
PY
        fi
        echo "Hadolint : $(grep -cE '(DL|SC)[0-9]{4}' "${DIR_REPORTES}/hadolint.txt" 2>/dev/null; true) observaciones"
    } > "${DIR_REPORTES}/resumen.txt"
    info "Resumen"
    cat "${DIR_REPORTES}/resumen.txt"
}

# ------------------------------------------------------------- Monitoreo
monitorear() {
    info "Monitoreo de ${ESTUDIANTE}"

    # 1. ¿La API responde?
    local respuesta codigo estado
    respuesta="$(curl -s -m 5 -w '\n%{http_code}' "$URL_HEALTH" 2>/dev/null)"
    codigo="$(tail -n1 <<< "$respuesta")"
    respuesta="$(head -n -1 <<< "$respuesta")"
    if [ "$codigo" = "200" ]; then
        estado="OK"
        ok "API responde en ${URL_HEALTH} (HTTP ${codigo}): ${respuesta}"
    else
        estado="FALLA"
        falla "API no responde correctamente en ${URL_HEALTH} (HTTP ${codigo:-sin respuesta})"
    fi

    # 2. Estado de los contenedores (solo los nuestros)
    echo -e "\nContenedores ${PREFIJO}_*:"
    docker ps -a --filter "name=^${PREFIJO}_" \
        --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

    # 3. Últimos registros de log
    echo -e "\nÚltimos logs de ${PREFIJO}_api:"
    docker logs --tail 10 "${PREFIJO}_api" 2>&1
    echo -e "\nÚltimos logs de ${PREFIJO}_db:"
    docker logs --tail 5 "${PREFIJO}_db" 2>&1

    # 4. Constancia con fecha en monitoreo.log
    local contenedores
    contenedores="$(docker ps -a --filter "name=^${PREFIJO}_" --format '{{.Names}}={{.Status}}' | paste -sd ';' -)"
    echo "[$(fecha)] estado=${estado} http=${codigo:-000} url=${URL_HEALTH} respuesta=${respuesta:-vacia} contenedores=${contenedores:-ninguno}" \
        >> "$LOG_MONITOREO"
    ok "Registro agregado a monitoreo.log"

    [ "$estado" = "OK" ]
}

# ---------------------------------------------------------------- main
case "${1:-todo}" in
    escanear)   escanear ;;
    monitorear) monitorear ;;
    todo)       escanear; monitorear ;;
    *)          echo "Uso: $0 [escanear|monitorear]"; exit 1 ;;
esac
