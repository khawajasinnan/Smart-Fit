from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator  # type: ignore[import]


class UserProfileInput(BaseModel):
    gender: str | None = None
    height_cm: float | None = None
    weight_kg: float | None = None
    chest_cm: float | None = None
    waist_cm: float | None = None
    hip_cm: float | None = None
    body_type: str | None = None
    skin_tone: str | None = None
    skin_undertone: str | None = None  # warm | cool | neutral (skin tone analyzer, 21 Nov 2026)
    usual_size: str | None = None  # the size the user says they buy, XS..4XL (onboarding, 21 Nov 2026)
    ethnicity: str | None = None
    style_preferences: list[str] = Field(default_factory=list)
    preferred_colors: list[str] = Field(default_factory=list)
    budget_min: int | None = None
    budget_max: int | None = None
    occasions: list[str] = Field(default_factory=list)

    @field_validator("budget_min", "budget_max")
    @classmethod
    def budget_must_be_positive(cls, value: int | None) -> int | None:
        if value is not None and value < 0:
            raise ValueError("Budget cannot be negative. Enter a positive PKR amount.")
        return value


class TasteProfile(BaseModel):
    """What the user's feedback taught us (spec §23.15): loves, "not for me"
    and quiz answers from the app and from notifications. Soft ranking
    signals; only excluded_product_ids is a hard filter."""

    liked_brands: list[str] = Field(default_factory=list, max_length=20)
    disliked_brands: list[str] = Field(default_factory=list, max_length=20)
    liked_colors: list[str] = Field(default_factory=list, max_length=20)
    disliked_colors: list[str] = Field(default_factory=list, max_length=20)
    liked_categories: list[str] = Field(default_factory=list, max_length=20)
    disliked_categories: list[str] = Field(default_factory=list, max_length=20)
    style_lean: Literal["eastern", "western"] | None = None
    price_point: int | None = Field(None, gt=0)
    excluded_product_ids: list[str] = Field(default_factory=list, max_length=500)


class ScrapeRecommendRequest(BaseModel):
    profile: UserProfileInput = Field(default_factory=UserProfileInput)
    user_message: str = ""
    assistant_message: str = ""
    chat_context: str = ""
    dynamic_prefs: dict = Field(default_factory=dict)
    max_products: int = 12
    taste: TasteProfile | None = None


class ExplanationFactor(BaseModel):
    """One reason a product ranked where it did (spec §23.25): a model
    feature, its value, and how far it moved the ranker's score."""

    feature: str
    label: str  # what the feature means, e.g. "colours that suit your skin tone"
    text: str  # the sentence for this product, e.g. "emerald flatters your Olive skin tone"
    value: float
    impact: float  # signed contribution to the LightGBM score (TreeSHAP)


class ProductRecommendation(BaseModel):
    id: str
    brand: str
    title: str
    category: str | None = None
    price_pkr: int | None = None
    currency: str = "PKR"
    image_url: str | None = None
    product_url: str
    sizes: list[str] = Field(default_factory=list)
    colors: list[str] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    match_score: int = 0
    match_reasons: list[str] = Field(default_factory=list)
    in_stock: bool = True
    recommended_size: str | None = None
    size_guidance: str | None = None
    # Accuracy (spec §23.12): when the store itself confirmed price and stock
    # (just before showing it), and when the catalog last read the product.
    price_checked_at: datetime | None = None
    catalog_updated_at: datetime | None = None
    # Learned ranking (spec §23.25). "rules" = the models aren't trained yet.
    ranking_model: str = "rules"
    ranker_score: float | None = Field(None, description="LightGBM, calibrated to 0..1")
    validator_score: float | None = Field(None, description="Random Forest P(good match), 0..1")
    validated: bool | None = Field(None, description="False: the validator disagreed and it was pulled down")
    explanation: list[ExplanationFactor] = Field(default_factory=list)
    suitability: dict[str, int | None] = Field(
        default_factory=dict, description="0..100 per aspect: skin_tone, colours, size, body_shape, occasion, budget")


class ScrapeRecommendResponse(BaseModel):
    products: list[ProductRecommendation]
    search_query: str
    brands_searched: list[str]
    message: str = ""
    stylist_message: str | None = None


# ── Spec §7.5 contract: POST /recommend (FashionCLIP over the catalog) ──────


class RecommendProfile(BaseModel):
    """Static profile inputs (spec §7.3)."""

    gender: str | None = Field(None, description="male | female")
    body_type: str | None = None
    skin_tone: str | None = None
    style_preferences: list[str] = Field(default_factory=list)
    # Body measurements from the profile (SFR-011), compared with each
    # product's own size chart. Without them no cross-system size guess is made.
    chest_cm: float | None = Field(None, gt=0)
    waist_cm: float | None = Field(None, gt=0)
    hip_cm: float | None = Field(None, gt=0)


class SessionInputs(BaseModel):
    """Chatbot session inputs (SFR-015)."""

    occasion: str | None = None
    mood: str | None = None
    color_pref: str | None = None
    budget_max: float | None = Field(None, gt=0, description="PKR")


class CvSummary(BaseModel):
    """The parts of cv-analysis output ranking uses (spec §6.3)."""

    body_type: str | None = None
    skin_tone: str | None = None
    estimated_size: str | None = Field(None, description="S | M | L | XL")


class RecommendRequest(BaseModel):
    profile: RecommendProfile = Field(default_factory=RecommendProfile)
    session_inputs: SessionInputs = Field(default_factory=SessionInputs)
    cv_analysis: CvSummary = Field(default_factory=CvSummary)
    top_n: int | None = Field(None, ge=1, le=50)


class Recommendation(BaseModel):
    product_id: str
    name: str
    image_url: str
    price: float
    similarity_score: float
    available_sizes: list[str]
    # Beyond the spec minimum: needed downstream (retailer link, try-on gate).
    product_url: str
    retailer: str
    category: str
    tryon_category: str | None = Field(None, description="None: unstitched fabric, not tried on")
    size_compatible: bool | None = Field(
        None, description="True: a fitting size is in stock. None: fit can't be determined (see size_note)."
    )
    recommended_size: str | None = Field(None, description="The product's own size label, e.g. '32' or 'M'")
    size_basis: str = Field("unknown", description="size_chart | label | unknown")
    size_note: str = ""


class RecommendResponse(BaseModel):
    recommendations: list[Recommendation]
    query_text: str
    catalog_size: int
    filtered_out: dict[str, int] = Field(default_factory=dict)
