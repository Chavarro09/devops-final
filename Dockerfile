FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Parches de seguridad del sistema base (Trivy: zlib1g CVE-2026-85091 HIGH)
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Usuario sin privilegios para ejecutar la aplicación
RUN useradd --create-home --shell /usr/sbin/nologin appuser

# pip actualizado (Trivy: CVE-2025-8869, CVE-2026-13346 y otras de pip 25.0.1)
COPY app/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip==26.3 \
    && pip install --no-cache-dir -r requirements.txt

COPY app/ .

USER appuser

# Dentro del contenedor la API siempre escucha en el puerto 5000
EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health', timeout=3)" || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--preload", "app:app"]
