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


class ScrapeRecommendRequest(BaseModel):
    profile: UserProfileInput = Field(default_factory=UserProfileInput)
    user_message: str = ""
    assistant_message: str = ""
    chat_context: str = ""
    dynamic_prefs: dict = Field(default_factory=dict)
    max_products: int = 12


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


class ScrapeRecommendResponse(BaseModel):
    products: list[ProductRecommendation]
    search_query: str
    brands_searched: list[str]
    message: str = ""
    stylist_message: str | None = None
