# Build context: backend/   ->   docker build -f services/hairstyle/Dockerfile backend
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY services/hairstyle/requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt

COPY shared/ shared/
COPY services/__init__.py services/__init__.py
COPY services/hairstyle/ services/hairstyle/
# Reused from the CV service: face detector, face mesh and face-shape rules (code + the two face models).
COPY services/cv_analysis/__init__.py services/cv_analysis/face.py services/cv_analysis/face_landmarks.py      services/cv_analysis/structure.py services/cv_analysis/body_classifier.py services/cv_analysis/hrnet.py      services/cv_analysis/
COPY services/cv_analysis/models/blaze_face_short_range.tflite services/cv_analysis/models/face_landmarker.task      services/cv_analysis/models/
# services/hairstyle/models/ (scripts/download_hairstyle_models.py) and catalog/
# (scripts/build_hairstyle_catalog.py) must be prepared before the build.

RUN useradd --create-home --uid 10001 smartfit
USER smartfit

EXPOSE 8006

CMD ["uvicorn", "services.hairstyle.main:app", "--host", "0.0.0.0", "--port", "8006"]
