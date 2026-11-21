# Build context: backend/   ->   docker build -f services/scraper/Dockerfile backend
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY services/scraper/requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt

COPY shared/ shared/
COPY services/__init__.py services/__init__.py
COPY services/scraper/ services/scraper/

RUN useradd --create-home --uid 10001 smartfit
USER smartfit

EXPOSE 8003

CMD ["uvicorn", "services.scraper.main:app", "--host", "0.0.0.0", "--port", "8003"]
