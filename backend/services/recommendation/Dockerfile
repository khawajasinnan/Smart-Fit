# Build context: backend/   ->   docker build -f services/recommendation/Dockerfile backend
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY services/recommendation/requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt

COPY shared/ shared/
COPY services/__init__.py services/__init__.py
COPY services/recommendation/ services/recommendation/

RUN useradd --create-home --uid 10001 smartfit
USER smartfit

EXPOSE 8002

CMD ["uvicorn", "services.recommendation.main:app", "--host", "0.0.0.0", "--port", "8002"]
