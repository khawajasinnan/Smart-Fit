# Build context: backend/   ->   docker build -f services/cv_analysis/Dockerfile backend
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# OpenCV (pulled in by MediaPipe) needs these shared libraries.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY services/cv_analysis/requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt
# Fail the build early if the CV stack can't import.
RUN python -c "import cv2, mediapipe"

COPY shared/ shared/
COPY services/__init__.py services/__init__.py
# models/ must already hold hrnet_w32_coco_256x192.onnx + face_landmarker.task
# (scripts/download_cv_models.py); without them the detailed scan skips those models.
COPY services/cv_analysis/ services/cv_analysis/

RUN useradd --create-home --uid 10001 smartfit
USER smartfit

EXPOSE 8001

CMD ["uvicorn", "services.cv_analysis.main:app", "--host", "0.0.0.0", "--port", "8001"]
