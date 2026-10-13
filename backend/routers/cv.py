"""FastAPI router for Computer Vision body analysis.

Endpoints:
  POST /cv/analyze  — Full body detection + pose estimation + skin tone
"""

from fastapi import APIRouter, HTTPException

from models.cv_schemas import CvAnalysisRequest, CvAnalysisResponse
from services.cv_analysis import analyze_body

router = APIRouter(prefix="/cv", tags=["computer-vision"])


@router.post("/analyze", response_model=CvAnalysisResponse)
async def cv_analyze(body: CvAnalysisRequest) -> CvAnalysisResponse:
    """Analyze a user photo for body shape, pose landmarks, size estimation,
    and skin tone.

    Accepts either an image URL or base64-encoded image.
    Optionally pass profile measurements (height_cm, chest_cm, etc.)
    to improve size estimation accuracy.

    SRDS refs: SFR-019 (body shape), SFR-020 (size estimation), SFR-021 (indicator)
    """
    if not body.image_url and not body.image_base64:
        raise HTTPException(
            status_code=422,
            detail="Provide either 'image_url' or 'image_base64'.",
        )

    try:
        result = await analyze_body(body)
        return result
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"CV analysis failed: {exc}",
        ) from exc
