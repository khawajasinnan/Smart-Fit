"""Settings shared by every SmartFit backend service.

Values come from environment variables (docker compose / Kubernetes) or, in
local development, from the single .env at the repository root. Each service
only reads the fields it needs; unknown variables are ignored.
"""

from pathlib import Path

from typing import Literal

from pydantic import AliasChoices, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def _repo_root_env() -> Path | None:
    # backend/shared/config.py -> parents[2] is the repository root. Inside a
    # container the path is shorter and there is no .env file — that's fine,
    # pydantic-settings simply skips a missing env_file.
    parents = Path(__file__).resolve().parents
    return parents[2] / ".env" if len(parents) > 2 else None


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=_repo_root_env(),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # ── General ──
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    cors_origins: str = "*"
    debug: bool = True

    # ── Supabase ──
    supabase_url: str = ""
    supabase_anon_key: str = ""
    supabase_jwt_secret: str = ""  # optional: legacy HS256 projects only
    # Service-role key: backend services only (Storage uploads, catalog and
    # config writes). Never shipped to the Flutter app.
    supabase_service_key: str = ""
    storage_bucket_tryon: str = "tryon-results"  # private bucket
    storage_bucket_hairstyle: str = "hairstyle-previews"  # private bucket
    signed_url_ttl_seconds: int = 3600

    # ── Gateway ──
    auth_required: bool = False
    admin_emails: str = "admin@smartfit.pk"
    max_body_bytes: int = 25_000_000
    proxy_timeout_seconds: float = 85.0
    rate_limit_chat_per_min: int = 20
    rate_limit_recommend_per_min: int = 10
    rate_limit_cv_per_min: int = 6
    rate_limit_default_per_min: int = 60
    rate_limit_face_check_per_min: int = 150  # camera frames while lining up (~2 a second)
    rate_limit_hairstyle_per_min: int = 10
    cv_analysis_url: str = "http://cv-analysis:8001"
    recommendation_url: str = "http://recommendation:8002"
    chat_orchestrator_url: str = "http://chat-orchestrator:8004"
    tryon_url: str = "http://tryon:8005"
    hairstyle_url: str = "http://hairstyle:8006"
    scoring_url: str = "http://scoring:8007"

    # ── Recommendation / scraper ──
    scraper_url: str = "http://scraper:8003"
    scraper_timeout_seconds: float = 75.0
    scrape_request_timeout: float = 30.0
    # Whole live search, all brands: whatever answered by then is returned.
    # Must stay below scraper_timeout_seconds (recommendation -> scraper).
    scrape_deadline_seconds: float = 45.0
    max_products_per_brand: int = 10
    max_total_products: int = 30
    # Re-check price and stock on the store before showing a product (spec §23.12).
    live_check_enabled: bool = True
    # Spec §23.25: LightGBM ranks + Random Forest validates the recommendations
    # (falls back to the rule ranking when false or when the models aren't trained).
    learned_ranking_enabled: bool = True
    # Spec §23.26: automatic learning from real users. Every AUTO_RETRAIN_HOURS
    # the services check for new feedback; with at least AUTO_RETRAIN_MIN_FEEDBACK
    # new reactions they retrain, and a new model replaces the current one only
    # if it is at least as good on held-out real feedback. 0 hours = off.
    auto_retrain_hours: float = 24.0
    auto_retrain_min_feedback: int = 50
    auto_retrain_min_look_ratings: int = 20
    # What the learned ranker showed each signed-in user (model inputs only),
    # joined with their loves / "not for me" to make real training rows.
    impression_logging_enabled: bool = True
    impression_retention_days: int = 180

    # ── Chat orchestrator (Gemini; LLM_API_KEY is accepted as an alias) ──
    gemini_api_key: str = Field("", validation_alias=AliasChoices("GEMINI_API_KEY", "LLM_API_KEY"))
    gemini_model: str = "gemini-2.5-flash"
    gemini_timeout_seconds: float = 55.0

    # ── CV analysis ──
    cv_allowed_image_hosts: str = ""  # comma-separated; the Supabase host is always allowed
    cv_max_image_bytes: int = 8_000_000
    cv_max_image_side: int = 1600

    # ── Models / Hugging Face ──
    huggingface_token: str = ""  # only for gated downloads; never logged

    # ── Try-on (the only GPU service) ──
    # IDM-VTON, chosen by the baseline comparison (spec §8.1, §23.8;
    # docs/evaluation/tryon_model_selection.md). The service refuses to load
    # a model while this is empty.
    tryon_model_name: Literal["", "idm-vton"] = ""
    tryon_lora_adapter_path: str = ""
    lora_weights_enabled: bool = False
    gpu_device: str = "cuda:0"
    max_concurrent_tryon_jobs: int = 1
    # Where try-on images are generated: "modal" = the GPU app in
    # services/tryon/modal_app.py (deployed with `modal deploy`), "mock" = TEST
    # MODE placeholder images for building the app without a GPU, "" = off
    # (the service answers 503 "not connected yet").
    tryon_backend: Literal["", "modal", "mock"] = ""
    tryon_modal_app: str = "smartfit-tryon"
    tryon_modal_class: str = "TryOn"
    # Hairstyle previews (spec §23.27): "modal" = HairFastGAN on the GPU app in
    # services/hairstyle/modal_app.py (real hair transfer, the user's own hair
    # replaced); "" = the CPU 2D overlay only.
    hairstyle_backend: Literal["", "modal"] = ""
    hairstyle_modal_app: str = "smartfit-hairstyle"
    hairstyle_modal_class: str = "HairFast"
    hairstyle_gpu_timeout_seconds: float = 150.0
    # Categories that use the DressCode LoRA adapter (spec §23.20); the rest use the base model.
    tryon_lora_categories: str = "upper,lower,dress"
    tryon_lora_version: str = "dresscode-v1"
    tryon_steps: int = 30
    tryon_seed: int = 42
    tryon_seconds_per_view: int = 30  # shown to the user as the estimate (measured 13 Nov: ~21 s per side on an A10G, plus transfer)
    tryon_mock_delay_seconds: float = 4.0
    tryon_job_ttl_seconds: int = 7200
    rate_limit_tryon_per_min: int = 4

    # ── Scraper ──
    scraper_user_agent: str = "SmartFitFYP/1.0 (academic project; contact: admin@smartfit.pk)"
    scraper_rate_limit_seconds: float = 2.0
    catalog_max_products: int = 600  # per brand per refresh: its newest in-stock adult clothing
    # Scheduled catalog refresh in the scraper service (0 = off; tests set 0).
    catalog_refresh_hours: float = 6.0
    catalog_refresh_start_delay_seconds: float = 120.0
    # Where the stores are read from: "local" = this machine, "modal" = the
    # cloud runner in services/scraper/modal_app.py (same polite rules; used
    # because Shopify rate-limits the developer's home IP, 13 Nov 2026).
    scraper_backend: Literal["local", "modal"] = "local"
    scraper_modal_app: str = "smartfit-scraper"
    # Remembers when the last scheduled refresh started, so restarting the
    # services doesn't start a new full refresh every time.
    catalog_refresh_state_path: str = str(Path(__file__).resolve().parents[1] / "data" / "catalog_refresh_state.json")

    # ── Catalog + recommendation (FashionCLIP) ──
    # Where the catalog lives: "auto" = Supabase when SUPABASE_SERVICE_KEY is
    # set, else the local snapshot; "snapshot"/"supabase" force one.
    catalog_store: Literal["auto", "supabase", "snapshot"] = "auto"
    # Local catalog snapshot, used when Supabase service access isn't configured.
    catalog_snapshot_path: str = str(Path(__file__).resolve().parents[1] / "data" / "catalog.jsonl")
    embedding_cache_path: str = str(
        Path(__file__).resolve().parents[1] / "services" / "recommendation" / "cache" / "embeddings.parquet"
    )
    fashionclip_model: str = "hf-hub:Marqo/marqo-fashionCLIP"
    # Load FashionCLIP + sync the catalog index at start-up (off in tests).
    fashionclip_autoload: bool = True
    # Brands whose product images FashionCLIP embeds (comma-separated keys; empty = all).
    # Embedding is CPU-heavy, so it stays on the original brands; the chat's
    # keyword search covers the whole catalog.
    fashionclip_retailers: str = "outfitters,breakout"
    recommend_top_n: int = 10

    @field_validator("debug", mode="before")
    @classmethod
    def parse_debug_mode(cls, value):
        if isinstance(value, str):
            normalized = value.strip().lower()
            if normalized in {"release", "prod", "production", "false", "0", "no", "off"}:
                return False
            if normalized in {"debug", "dev", "development", "true", "1", "yes", "on"}:
                return True
        return value

    @property
    def cors_origin_list(self) -> list[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def admin_email_list(self) -> list[str]:
        return [e.strip().lower() for e in self.admin_emails.split(",") if e.strip()]


settings = Settings()
