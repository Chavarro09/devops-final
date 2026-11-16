"""API de tareas - Proyecto final DevOps.

Expone un CRUD de tareas sobre PostgreSQL y escribe un log en formato JSON
por cada petición, hacia la salida estándar (visible con `docker logs`).
"""
import json
import logging
import os
import sys
import time
from contextlib import contextmanager
from datetime import datetime, timezone

import psycopg2
from psycopg2.extras import RealDictCursor
from flask import Flask, g, jsonify, request

app = Flask(__name__)

# ---------------------------------------------------------------- logs
logger = logging.getLogger("api")
_handler = logging.StreamHandler(sys.stdout)
_handler.setFormatter(logging.Formatter("%(message)s"))
logger.addHandler(_handler)
logger.setLevel(logging.INFO)


def log(nivel, mensaje, **extra):
    """Escribe una línea de log en formato JSON."""
    registro = {
        "fecha": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "nivel": nivel,
        "mensaje": mensaje,
        **extra,
    }
    logger.info(json.dumps(registro, ensure_ascii=False))


# ------------------------------------------------------- base de datos
def conectar():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "db"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("POSTGRES_DB", "tareas"),
        user=os.getenv("POSTGRES_USER", "postgres"),
        password=os.getenv("POSTGRES_PASSWORD", ""),
        connect_timeout=3,
    )


@contextmanager
def cursor():
    conn = conectar()
    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                yield cur
    finally:
        conn.close()


def inicializar_db(intentos=10, espera=3):
    """Crea la tabla si no existe. Reintenta mientras la BD arranca."""
    for intento in range(1, intentos + 1):
        try:
            with cursor() as cur:
                cur.execute(
                    """CREATE TABLE IF NOT EXISTS tareas (
                           id         SERIAL PRIMARY KEY,
                           titulo     TEXT NOT NULL,
                           completada BOOLEAN NOT NULL DEFAULT FALSE,
                           creada     TIMESTAMPTZ NOT NULL DEFAULT NOW()
                       )"""
                )
            log("INFO", "Base de datos lista")
            return
        except psycopg2.OperationalError as error:
            log("WARNING", "Base de datos no disponible, reintentando",
                intento=intento, error=str(error).strip())
            time.sleep(espera)
    log("ERROR", "No fue posible conectar con la base de datos")


def serializar(fila):
    fila = dict(fila)
    fila["creada"] = fila["creada"].isoformat(timespec="seconds")
    return fila


# ------------------------------------------------- registro de peticiones
@app.before_request
def marcar_inicio():
    g.inicio = time.perf_counter()


@app.after_request
def registrar_peticion(respuesta):
    duracion = (time.perf_counter() - g.get("inicio", time.perf_counter())) * 1000
    log("INFO", "peticion",
        metodo=request.method,
        ruta=request.path,
        estado=respuesta.status_code,
        duracion_ms=round(duracion, 2),
        ip=request.headers.get("X-Forwarded-For", request.remote_addr))
    return respuesta


@app.errorhandler(psycopg2.Error)
def error_bd(error):
    log("ERROR", "Error de base de datos", error=str(error).strip())
    return jsonify(error="Base de datos no disponible"), 503


# ------------------------------------------------------------ endpoints
@app.get("/")
def inicio():
    return jsonify(servicio="API de tareas",
                   estudiante=os.getenv("ESTUDIANTE", "sin asignar"),
                   version="1.0.0")


@app.get("/health")
def health():
    try:
        with cursor() as cur:
            cur.execute("SELECT 1")
        return jsonify(estado="ok", base_de_datos="conectada"), 200
    except psycopg2.Error:
        return jsonify(estado="error", base_de_datos="desconectada"), 503


@app.get("/tareas")
def listar_tareas():
    with cursor() as cur:
        cur.execute("SELECT * FROM tareas ORDER BY id")
        return jsonify([serializar(f) for f in cur.fetchall()])


@app.post("/tareas")
def crear_tarea():
    datos = request.get_json(silent=True) or {}
    titulo = str(datos.get("titulo", "")).strip()
    if not titulo:
        return jsonify(error="El campo 'titulo' es obligatorio"), 400
    with cursor() as cur:
        cur.execute("INSERT INTO tareas (titulo) VALUES (%s) RETURNING *", (titulo,))
        return jsonify(serializar(cur.fetchone())), 201


@app.put("/tareas/<int:tarea_id>")
def actualizar_tarea(tarea_id):
    datos = request.get_json(silent=True) or {}
    with cursor() as cur:
        cur.execute(
            """UPDATE tareas
                  SET titulo = COALESCE(%s, titulo),
                      completada = COALESCE(%s, completada)
                WHERE id = %s RETURNING *""",
            (datos.get("titulo"), datos.get("completada"), tarea_id),
        )
        fila = cur.fetchone()
    if fila is None:
        return jsonify(error="Tarea no encontrada"), 404
    return jsonify(serializar(fila))


@app.delete("/tareas/<int:tarea_id>")
def eliminar_tarea(tarea_id):
    with cursor() as cur:
        cur.execute("DELETE FROM tareas WHERE id = %s RETURNING id", (tarea_id,))
        fila = cur.fetchone()
    if fila is None:
        return jsonify(error="Tarea no encontrada"), 404
    return jsonify(mensaje="Tarea eliminada", id=tarea_id)


inicializar_db()
