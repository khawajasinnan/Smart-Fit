from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import logging

from core.config import settings
from routers.cv import router as cv_router
from routers.scrape import router as scrape_router

# ── Logging ──
logging.basicConfig(
    level=logging.DEBUG if settings.debug else logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("smartfit")

app = FastAPI(
    title="SmartFit API",
    description="Backend for AI stylist product scraping and recommendations (Pakistan)",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(scrape_router, prefix="/api/v1")
app.include_router(cv_router, prefix="/api/v1")


@app.get("/health")
async def health():
    return {"status": "ok", "service": "smartfit-api"}


if __name__ == "__main__":
    import uvicorn

    logger.info("Starting SmartFit API on %s:%s", settings.api_host, settings.api_port)
    uvicorn.run(
        "main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=True,
    )
