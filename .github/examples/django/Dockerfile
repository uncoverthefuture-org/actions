# syntax=docker/dockerfile:1
FROM python:3.11-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /app/
RUN if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
COPY . /app
EXPOSE 8000
ENV TARGET_PORT=8000
CMD sh -c "gunicorn ${DJANGO_WSGI_MODULE:-project.wsgi}:application -b 0.0.0.0:${TARGET_PORT:-8000}"
