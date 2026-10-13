"""Pakistani fashion brand configurations with VERIFIED collection slugs.

Each slug has been tested against the Shopify JSON products API to confirm
it returns actual products.  Brands whose JSON API is blocked (Khaadi,
Sapphire, Cambridge) are kept for HTML scraping only.

BRAND CATEGORY MAPPING:
  Each brand has a `strength` field indicating what outfit categories it
  excels at.  When a user asks for "pent coat" we only query brands
  that stock Western formal suits — not kurta/shalwar shops.
"""

from dataclasses import dataclass, field


@dataclass(frozen=True)
class BrandConfig:
    name: str
    base_url: str
    collection_slugs: dict[str, list[str]]
    # If True, skip Shopify JSON and only use HTML scraping
    html_only: bool = False
    # Category strengths — only brands matching the requested category are scraped
    # Empty means "general / all categories"
    strengths: frozenset[str] = field(default_factory=frozenset)


# ══════════════════════════════════════════════════════════════════════════════
# BRAND ↔ CATEGORY STRENGTH MAP
# When user requests a specific category, ONLY brands with that strength
# (or empty = "general") are queried.  This prevents kurta brands from
# polluting pent coat results and vice versa.
# ══════════════════════════════════════════════════════════════════════════════
_WESTERN_FORMAL = frozenset({
    "two-piece-suit", "three-piece-suit", "blazer", "formal-shirt", "trouser",
})
_EASTERN_MALE = frozenset({
    "shalwar-kameez", "kurta", "waistcoat", "sherwani", "prince-coat",
})
_CASUAL = frozenset({
    "casual-shirt", "t-shirt", "polo-shirt", "jeans", "chinos", "hoodie",
    "jacket", "sweater", "shorts", "coat",
})
_WOMEN_EASTERN = frozenset({
    "kurti", "lawn-suit", "unstitched", "pret", "ladies-formal", "bridal",
    "gharara", "sharara", "anarkali", "frock", "maxi-dress", "abaya",
})
_WOMEN_BRIDAL = frozenset({"bridal", "wedding", "formal", "nikah", "baraat", "walima", "mehndi", "party wear", "luxury pret"})
_WOMEN_LUXURY = frozenset({"luxury pret", "couture", "designer", "formals", "festive", "chiffon", "velvet", "organza"})
_WOMEN_LAWN = frozenset({"lawn suit", "lawn", "cambric", "cotton", "unstitched", "pret", "printed"})
_WOMEN_CASUAL_WESTERN = frozenset({"jeans", "tops", "t-shirts", "co-ord set", "western", "casual", "denim", "pants"})
_WOMEN_WINTER = frozenset({"khaddar", "linen", "velvet", "karandi", "winter", "shawl"})
_ALL = frozenset()  # empty = matches everything


# ── Verified Shopify-JSON brands ────────────────────────────────────
PAKISTANI_BRANDS: list[BrandConfig] = [
    BrandConfig(
        name="Outfitters",
        base_url="https://outfitters.com.pk",
        collection_slugs={
            "female": [
                "women-tops",
                "women-dresses",
                "women-jeans",
                "women-trousers",
                "women-t-shirts",
            ],
            "male": [
                "men-shirts",
                "men-trousers",
                "men-t-shirts",
                "men-jeans",
                "men-jackets",
            ],
            "unisex": ["men-shirts", "women-tops"],
        },
        strengths=_CASUAL,
    ),
    BrandConfig(
        name="Breakout",
        base_url="https://www.breakout.com.pk",
        collection_slugs={
            "female": ["women"],
            "male": ["men"],
            "unisex": ["men"],
        },
        strengths=_CASUAL,
    ),
    BrandConfig(
        name="Bonanza Satrangi",
        base_url="https://www.bonanzasatrangi.com",
        collection_slugs={
            "female": ["women", "pret"],
            "male": ["men"],
            "unisex": ["men"],
        },
        strengths=_EASTERN_MALE | _WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Cougar",
        base_url="https://www.cougar.com.pk",
        collection_slugs={
            "female": ["women"],
            "male": ["men"],
            "unisex": ["men"],
        },
        strengths=_CASUAL,
    ),
    BrandConfig(
        name="Muraqsh Man",
        base_url="https://www.muraqshman.com",
        collection_slugs={
            "female": [],
            "male": ["kurta-waistcoat-set", "kurta-trouser"],
            "unisex": ["kurta-waistcoat-set"],
        },
        strengths=_EASTERN_MALE,
    ),
    BrandConfig(
        name="Kurta Corner",
        base_url="https://kurtacorner.com",
        collection_slugs={
            "female": [],
            "male": ["waist-coat", "kurta"],
            "unisex": ["kurta"],
        },
        strengths=_EASTERN_MALE,
    ),
    BrandConfig(
        name="Nishat Linen",
        base_url="https://nishatlinen.com",
        collection_slugs={
            "female": ["women-stitched", "women-unstitched", "ready-to-wear"],
            "male": ["men-stitched", "men-unstitched"],
            "unisex": ["men-stitched"],
        },
        strengths=_EASTERN_MALE | _WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Limelight",
        base_url="https://www.limelight.pk",
        collection_slugs={
            "female": ["ready-to-wear", "pret"],
            "male": ["menswear"],
            "unisex": ["menswear"],
        },
        strengths=_WOMEN_EASTERN | _EASTERN_MALE,
    ),
    BrandConfig(
        name="Almirah",
        base_url="https://www.almirah.com.pk",
        collection_slugs={
            "female": ["women-ready-to-wear", "women"],
            "male": ["men"],
            "unisex": ["men"],
        },
        strengths=_EASTERN_MALE | _WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Edenrobe",
        base_url="https://edenrobe.com",
        collection_slugs={
            "female": ["women-pret", "women-unstitched"],
            "male": ["men", "men-suits", "men-ceremonial"],
            "unisex": ["men"],
        },
        strengths=_EASTERN_MALE | _WESTERN_FORMAL | _WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Charcoal",
        base_url="https://www.charcoal.com.pk",
        collection_slugs={
            "female": [],
            "male": ["suiting", "blazers", "casual-coats", "all"],
            "unisex": ["all"],
        },
        strengths=_WESTERN_FORMAL | _CASUAL,
    ),
    # ── HTML-only brands (Shopify JSON blocked or non-Shopify) ──
    BrandConfig(
        name="Junaid Jamshed",
        base_url="https://www.junaidjamshed.com",
        collection_slugs={
            "female": [
                "women-kurti",
                "women-stitched",
                "women-unstitched",
            ],
            "male": [
                "men-kurta",
                "men-waistcoat",
            ],
            "unisex": ["men-kurta"],
        },
        html_only=True,
        strengths=_EASTERN_MALE | _WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Khaadi",
        base_url="https://www.khaadi.com",
        collection_slugs={
            "female": ["ready-to-wear", "pret", "new-in"],
            "male": ["man"],
            "unisex": ["new-in"],
        },
        html_only=True,
        strengths=_WOMEN_EASTERN | _EASTERN_MALE,
    ),
    BrandConfig(
        name="Sapphire",
        base_url="https://pk.sapphireonline.pk",
        collection_slugs={
            "female": ["ready-to-wear", "new-in"],
            "male": ["man"],
            "unisex": ["new-in"],
        },
        html_only=True,
        strengths=_WOMEN_EASTERN | _EASTERN_MALE,
    ),
    BrandConfig(
        name="Cambridge",
        base_url="https://thecambridgeshop.com",
        collection_slugs={
            "female": ["women"],
            "male": [
                "formal-suits",
                "blazers",
                "formal-shirts",
                "bottoms",
            ],
            "unisex": ["formal-shirts"],
        },
        html_only=True,
        strengths=_WESTERN_FORMAL,
    ),
    BrandConfig(
        name="Royal Tag",
        base_url="https://royaltag.pk",
        collection_slugs={
            "female": [],
            "male": ["suits", "blazers", "formal-shirts", "trousers"],
            "unisex": ["suits"],
        },
        html_only=True,
        strengths=_WESTERN_FORMAL,
    ),
    BrandConfig(
        name="Uniworth",
        base_url="https://uniworthshop.com",
        collection_slugs={
            "female": [],
            "male": ["suiting", "shirts", "trousers", "ethnic-wear", "casual-wear"],
            "unisex": ["suiting"],
        },
        strengths=_WESTERN_FORMAL | _EASTERN_MALE | _CASUAL,
    ),
    BrandConfig(
        name="Rici Melion",
        base_url="https://ricimelion.com",
        collection_slugs={
            "female": [],
            "male": ["suiting", "suits", "blazers", "kurta", "sherwani", "prince-coat", "waistcoat", "shirts", "casuals"],
            "unisex": ["suiting"],
        },
        strengths=_WESTERN_FORMAL | _EASTERN_MALE | _CASUAL,
    ),
    BrandConfig(
        name="Sana Safinaz",
        base_url="https://www.sanasafinaz.com",
        collection_slugs={
            "female": ["ready-to-wear", "pret", "unstitched", "new-arrivals"],
            "male": [],
            "unisex": ["ready-to-wear"],
        },
        strengths=_WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Maria.B",
        base_url="https://www.mariab.pk",
        collection_slugs={
            "female": ["ready-to-wear", "pret", "unstitched", "lawn"],
            "male": [],
            "unisex": ["ready-to-wear"],
        },
        strengths=_WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Kayseria",
        base_url="https://www.kayseria.com",
        collection_slugs={
            "female": ["ready-to-wear", "pret", "unstitched"],
            "male": [],
            "unisex": ["ready-to-wear"],
        },
        strengths=_WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Ideas (Gul Ahmed)",
        base_url="https://www.gulahmedshop.com",
        collection_slugs={
            "female": ["women-stitched", "women-unstitched", "pret"],
            "male": ["men-kurtas", "men"],
            "unisex": ["men"],
        },
        html_only=True,
        strengths=_EASTERN_MALE | _WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Ethnic",
        base_url="https://ethnic.pk",
        collection_slugs={
            "female": ["ready-to-wear", "unstitched", "formal"],
            "male": ["men", "men-kurta"],
            "unisex": ["men"],
        },
        html_only=True,
        strengths=_EASTERN_MALE | _WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Leisure Club",
        base_url="https://www.leisureclub.pk",
        collection_slugs={
            "female": ["women-new-arrivals", "women-tops"],
            "male": ["men-new-arrivals", "men-t-shirts", "men-trousers"],
            "unisex": ["men-new-arrivals"],
        },
        html_only=True,
        strengths=_CASUAL,
    ),
    BrandConfig(
        name="Diners",
        base_url="https://diners.com.pk",
        collection_slugs={
            "female": ["women"],
            "male": ["men-casual-shirts", "men-t-shirts", "men-trousers", "men-jeans"],
            "unisex": ["men-casual-shirts"],
        },
        html_only=True,
        strengths=_CASUAL,
    ),
    BrandConfig(
        name="Generation",
        base_url="https://generation.com.pk",
        collection_slugs={
            "female": ["pret", "unstitched", "new-arrivals"],
            "male": [],
            "unisex": ["new-arrivals"],
        },
        html_only=True,
        strengths=_WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Beechtree",
        base_url="https://beechtree.pk",
        collection_slugs={
            "female": ["ready-to-wear", "pret", "new-in"],
            "male": [],
            "unisex": ["new-in"],
        },
        html_only=True,
        strengths=_WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Ego",
        base_url="https://ego.pk",
        collection_slugs={
            "female": ["pret", "kurtas", "bottoms"],
            "male": [],
            "unisex": ["pret"],
        },
        html_only=True,
        strengths=_WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Rang Ja",
        base_url="https://rangja.com",
        collection_slugs={
            "female": ["pret", "ready-to-wear", "new-arrivals"],
            "male": [],
            "unisex": ["new-arrivals"],
        },
        html_only=True,
        strengths=_WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Zellbury",
        base_url="https://zellbury.com",
        collection_slugs={
            "female": ["ready-to-wear", "unstitched", "women"],
            "male": ["men", "menswear"],
            "unisex": ["ready-to-wear"],
        },
        strengths=_EASTERN_MALE | _WOMEN_EASTERN | _CASUAL,
    ),
    BrandConfig(
        name="Shahzeb Saeed",
        base_url="https://shahzebsaeed.com",
        collection_slugs={
            "female": [],
            "male": ["mens-shirts", "mens-kurtas", "pajamas-trousers", "men-bottoms", "all"],
            "unisex": ["all"],
        },
        strengths=_EASTERN_MALE | _CASUAL | _WESTERN_FORMAL,
    ),
    BrandConfig(
        name="Alkaram Studio",
        base_url="https://www.alkaramstudio.com",
        collection_slugs={
            "female": ["ready-to-wear", "women-rtw-shirt-trouser", "women-rtw-shirt-trouser-dupatta", "women-rtw-shirt"],
            "male": ["men-ready-to-wear", "men-rtw-kurta", "men-rtw-kurta-trouser", "men-rtw-waistcoat"],
            "unisex": ["ready-to-wear"],
        },
        strengths=_WOMEN_EASTERN | _EASTERN_MALE,
    ),
    BrandConfig(
        name="Cross Stitch",
        base_url="https://crossstitch.pk",
        collection_slugs={
            "female": ["ready-to-wear", "ready-to-wear-2piece", "ready-to-wear-3piece", "basic-pret", "luxury-pret"],
            "male": ["menswear"],
            "unisex": ["ready-to-wear"],
        },
        strengths=_WOMEN_EASTERN | _EASTERN_MALE,
    ),
    BrandConfig(
        name="Zaha",
        base_url="https://zaha.pk",
        collection_slugs={
            "female": ["ready-to-wear", "zaha-rtw-artisan-prints", "zaha-rtw-pop", "new-arrivals"],
            "male": [],
            "unisex": ["ready-to-wear"],
        },
        strengths=_WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Bareeze",
        base_url="https://www.bareeze.com",
        collection_slugs={
            "female": ["ready-to-wear", "pret", "unstitched", "luxury-pret"],
            "male": [],
            "unisex": ["ready-to-wear"],
        },
        html_only=True,
        strengths=_WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Agha Noor",
        base_url="https://aghanoor.com",
        collection_slugs={
            "female": ["ready-to-wear", "pret", "formals", "new-arrivals"],
            "male": [],
            "unisex": ["ready-to-wear"],
        },
        strengths=_WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Hussain Rehar",
        base_url="https://hussainrehar.com",
        collection_slugs={
            "female": ["pret", "luxury-pret", "bridal", "formals"],
            "male": [],
            "unisex": ["pret"],
        },
        strengths=_WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Amir Adnan",
        base_url="https://amiradnan.com",
        collection_slugs={
            "female": ["women"],
            "male": ["sherwani", "waistcoat", "kurta", "formal-suits", "prince-coat"],
            "unisex": ["sherwani"],
        },
        html_only=True,
        strengths=_EASTERN_MALE | _WESTERN_FORMAL,
    ),
    BrandConfig(
        name="Deepak Perwani",
        base_url="https://deepakperwani.com",
        collection_slugs={
            "female": ["women"],
            "male": ["sherwani", "prince-coat", "waistcoat", "formal"],
            "unisex": ["sherwani"],
        },
        html_only=True,
        strengths=_EASTERN_MALE | _WESTERN_FORMAL,
    ),
    BrandConfig(
        name="Penny",
        base_url="https://pennystore.pk",
        collection_slugs={
            "female": ["women"],
            "male": ["men", "t-shirts", "jeans", "hoodies"],
            "unisex": ["men"],
        },
        strengths=_CASUAL,
    ),
    BrandConfig(
        name="Stone Harbor",
        base_url="https://stoneharbor.pk",
        collection_slugs={
            "female": ["women"],
            "male": ["men", "polo-shirts", "t-shirts", "jeans", "jackets"],
            "unisex": ["men"],
        },
        strengths=_CASUAL,
    ),
    BrandConfig(
        name="Motifz",
        base_url="https://motifz.com.pk",
        collection_slugs={
            "female": ["ready-to-wear", "pret", "unstitched", "luxury-pret"],
            "male": ["men"],
            "unisex": ["ready-to-wear"],
        },
        strengths=_WOMEN_EASTERN | _EASTERN_MALE,
    ),
    BrandConfig(
        name="Asim Jofa",
        base_url="https://asimjofa.com",
        collection_slugs={
            "female": ["luxury-pret", "lawn", "bridal", "formals", "festive", "chiffon"],
            "male": [],
            "unisex": ["luxury-pret"],
        },
        strengths=_WOMEN_BRIDAL | _WOMEN_LUXURY | _WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Mushq",
        base_url="https://mushq.pk",
        collection_slugs={
            "female": ["luxury-pret", "formals", "festive", "chiffon", "pret"],
            "male": [],
            "unisex": ["luxury-pret"],
        },
        strengths=_WOMEN_LUXURY | _WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Baroque",
        base_url="https://baroque.pk",
        collection_slugs={
            "female": ["luxury-lawn", "chiffon", "velvet", "pret", "unstitched"],
            "male": [],
            "unisex": ["pret"],
        },
        strengths=_WOMEN_LAWN | _WOMEN_LUXURY | _WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Crimson",
        base_url="https://crimson.com.pk",
        collection_slugs={
            "female": ["luxury-lawn", "formals", "pret", "chiffon"],
            "male": [],
            "unisex": ["pret"],
        },
        strengths=_WOMEN_LUXURY | _WOMEN_LAWN,
    ),
    BrandConfig(
        name="Mohagni",
        base_url="https://mohagni.com",
        collection_slugs={
            "female": ["lawn", "pret", "unstitched", "cotton"],
            "male": [],
            "unisex": ["pret"],
        },
        strengths=_WOMEN_LAWN | _WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Firdous",
        base_url="https://firdous.com",
        collection_slugs={
            "female": ["lawn", "cotton", "chiffon", "unstitched"],
            "male": [],
            "unisex": ["lawn"],
        },
        strengths=_WOMEN_LAWN | _WOMEN_EASTERN,
    ),
    BrandConfig(
        name="So Kamal",
        base_url="https://sokamal.com",
        collection_slugs={
            "female": ["pret", "unstitched", "lawn", "winter"],
            "male": [],
            "unisex": ["pret"],
        },
        strengths=_WOMEN_LAWN | _WOMEN_EASTERN | _WOMEN_WINTER,
    ),
    BrandConfig(
        name="Maryam Hussain",
        base_url="https://maryamhussain.com",
        collection_slugs={
            "female": ["formals", "bridal", "luxury-pret", "festive"],
            "male": [],
            "unisex": ["formals"],
        },
        strengths=_WOMEN_BRIDAL | _WOMEN_LUXURY,
    ),
    BrandConfig(
        name="Saya",
        base_url="https://sfrapparel.com",
        collection_slugs={
            "female": ["unstitched", "pret", "lawn", "western"],
            "male": [],
            "unisex": ["pret"],
        },
        strengths=_WOMEN_LAWN | _WOMEN_EASTERN | _WOMEN_CASUAL_WESTERN,
    ),
    BrandConfig(
        name="Warda",
        base_url="https://wfrapparel.com",
        collection_slugs={
            "female": ["lawn", "pret", "winter", "unstitched"],
            "male": [],
            "unisex": ["pret"],
        },
        strengths=_WOMEN_LAWN | _WOMEN_EASTERN | _WOMEN_WINTER,
    ),
    BrandConfig(
        name="Serene",
        base_url="https://serenepremium.com",
        collection_slugs={
            "female": ["premium-lawn", "chiffon", "velvet", "pret"],
            "male": [],
            "unisex": ["pret"],
        },
        strengths=_WOMEN_LUXURY | _WOMEN_LAWN,
    ),
    BrandConfig(
        name="Ittehad",
        base_url="https://ittehadtextiles.com",
        collection_slugs={
            "female": ["lawn", "linen", "winter", "unstitched"],
            "male": [],
            "unisex": ["lawn"],
        },
        strengths=_WOMEN_LAWN | _WOMEN_WINTER | _WOMEN_EASTERN,
    ),
    BrandConfig(
        name="Faraz Manan",
        base_url="https://farazmanan.com",
        collection_slugs={
            "female": ["bridal", "couture", "formals"],
            "male": [],
            "unisex": ["formals"],
        },
        html_only=True,
        strengths=_WOMEN_BRIDAL | _WOMEN_LUXURY,
    ),
    BrandConfig(
        name="Minnie Minors",
        base_url="https://minnieminors.com",
        collection_slugs={
            "female": ["girls", "women", "western"],
            "male": [],
            "unisex": ["western"],
        },
        strengths=_WOMEN_CASUAL_WESTERN,
    ),
]


def normalize_gender(gender: str | None) -> str:
    if not gender:
        return "female"
    g = gender.strip().lower()
    if g in {"male", "m", "man", "men"}:
        return "male"
    if g in {"female", "f", "woman", "women"}:
        return "female"
    return "unisex"
