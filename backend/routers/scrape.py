from fastapi import APIRouter, HTTPException

from models.schemas import ScrapeRecommendRequest, ScrapeRecommendResponse
from services.scraper_service import recommend_products

router = APIRouter(prefix="/scrape", tags=["scrape"])


@router.post("/recommend", response_model=ScrapeRecommendResponse)
async def scrape_recommend(body: ScrapeRecommendRequest) -> ScrapeRecommendResponse:
    """
    Scrape Pakistani fashion retailers and rank products for the user's
    static profile (measurements, skin tone, style) and dynamic chat context.
    """
    try:
        return await recommend_products(body)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Scraping failed: {exc}",
        ) from exc
