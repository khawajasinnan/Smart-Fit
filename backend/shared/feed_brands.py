"""Pakistani brands whose official stores publish a product feed (Shopify
/products.json, allowed by their robots.txt). The catalog is synced from
these every CATALOG_REFRESH_HOURS (spec §10, §23.12).

Checked 8 Nov 2026, one request at a time: each base_url returned products.
Not here because they publish no feed (or didn't answer): Breakout (manual
CSV import instead), Khaadi, Sapphire, Kayseria, Leisure Club, Rang Ja,
Bareeze, Deepak Perwani, Ittehad, Faraz Manan, Mushq (rate-limited the
check), Firdous, Warda, Charizma, Lakhany, Hem Stitch, Phatyma Khan, Mahgul,
Asifa & Nabeel, Nakoosh, Penny, Maryam Hussain.

audience: who the brand sells clothing to. A product's own tags/title/type
decide its gender; the audience is used only when they say nothing, and a
"both" brand's unlabelled products are skipped rather than guessed.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

Audience = Literal["men", "women", "both"]


@dataclass(frozen=True)
class FeedBrand:
    key: str  # product_id prefix and `retailer` column, e.g. "bonanza-satrangi"
    name: str  # shown in the app
    base_url: str
    audience: Audience
    # Shop id the size-chart app expects (seen in the store's page script); Outfitters only.
    size_chart_shop: str | None = None


FEED_BRANDS: tuple[FeedBrand, ...] = (
    # ── men and women ──
    FeedBrand("outfitters", "Outfitters", "https://outfitters.com.pk", "both", "outfitterspk.myshopify.com"),
    FeedBrand("bonanza-satrangi", "Bonanza Satrangi", "https://www.bonanzasatrangi.com", "both"),
    FeedBrand("cougar", "Cougar", "https://www.cougar.com.pk", "both"),
    FeedBrand("almirah", "Almirah", "https://www.almirah.com.pk", "both"),
    FeedBrand("edenrobe", "Edenrobe", "https://edenrobe.com", "both"),
    FeedBrand("junaid-jamshed", "Junaid Jamshed", "https://www.junaidjamshed.com", "both"),
    FeedBrand("gul-ahmed", "Ideas (Gul Ahmed)", "https://www.gulahmedshop.com", "both"),
    FeedBrand("maria-b", "Maria.B", "https://www.mariab.pk", "both"),
    FeedBrand("diners", "Diners", "https://diners.com.pk", "both"),
    FeedBrand("zellbury", "Zellbury", "https://zellbury.com", "both"),
    FeedBrand("alkaram-studio", "Alkaram Studio", "https://www.alkaramstudio.com", "both"),
    FeedBrand("nishat-linen", "Nishat Linen", "https://nishatlinen.com", "both"),
    FeedBrand("limelight", "Limelight", "https://www.limelight.pk", "both"),
    FeedBrand("ethnic", "Ethnic", "https://pk.ethnc.com", "both"),
    FeedBrand("stone-harbor", "Stone Harbor", "https://www.stoneharbor.com.pk", "both"),
    FeedBrand("engine", "Engine", "https://engine.com.pk", "both"),
    FeedBrand("furor", "Furor", "https://furorjeans.com", "both"),
    FeedBrand("rastah", "Rastah", "https://rastah.co", "both"),
    # ── men ──
    FeedBrand("muraqsh-man", "Muraqsh Man", "https://www.muraqshman.com", "men"),
    FeedBrand("kurta-corner", "Kurta Corner", "https://kurtacorner.com", "men"),
    FeedBrand("charcoal", "Charcoal", "https://www.charcoal.com.pk", "men"),
    FeedBrand("cambridge", "Cambridge", "https://thecambridgeshop.com", "men"),
    FeedBrand("royal-tag", "Royal Tag", "https://royaltag.com.pk", "men"),
    FeedBrand("uniworth", "Uniworth", "https://uniworthshop.com", "men"),
    FeedBrand("rici-melion", "Rici Melion", "https://ricimelion.com", "men"),
    FeedBrand("shahzeb-saeed", "Shahzeb Saeed", "https://shahzebsaeed.com", "men"),
    FeedBrand("amir-adnan", "Amir Adnan", "https://amiradnan.com", "men"),
    FeedBrand("monark", "Monark", "https://monark.com.pk", "men"),
    # ── women ──
    FeedBrand("sana-safinaz", "Sana Safinaz", "https://www.sanasafinaz.com", "women"),
    FeedBrand("generation", "Generation", "https://generation.com.pk", "women"),
    FeedBrand("beechtree", "Beechtree", "https://beechtree.pk", "women"),
    FeedBrand("ego", "Ego", "https://wearego.com", "women"),
    FeedBrand("cross-stitch", "Cross Stitch", "https://crossstitch.pk", "women"),
    FeedBrand("zaha", "Zaha", "https://zaha.pk", "women"),
    FeedBrand("agha-noor", "Agha Noor", "https://aghanoorbridal.com", "women"),
    FeedBrand("hussain-rehar", "Hussain Rehar", "https://hussainrehar.com", "women"),
    FeedBrand("motifz", "Motifz", "https://motifz.com.pk", "women"),
    FeedBrand("asim-jofa", "Asim Jofa", "https://asimjofa.com", "women"),
    FeedBrand("baroque", "Baroque", "https://baroque.pk", "women"),
    FeedBrand("crimson", "Crimson", "https://crimson.com.pk", "women"),
    FeedBrand("mohagni", "Mohagni", "https://mohagni.com", "women"),
    FeedBrand("so-kamal", "So Kamal", "https://sokamal.com", "women"),
    FeedBrand("saya", "Saya", "https://saya.pk", "women"),
    FeedBrand("serene", "Serene", "https://serenepremium.com", "women"),
    FeedBrand("lulusar", "Lulusar", "https://lulusar.com", "women"),
    FeedBrand("zeen", "Zeen", "https://zeenwoman.com", "women"),
    FeedBrand("bin-saeed", "Bin Saeed", "https://binsaeedfabric.com", "women"),
    FeedBrand("maryum-n-maria", "Maryum N Maria", "https://maryumnmaria.com", "women"),
    FeedBrand("jazmin", "Jazmin", "https://jazmin.pk", "women"),
    FeedBrand("mausummery", "Mausummery", "https://mausummery.com", "women"),
    FeedBrand("chinyere", "Chinyere", "https://chinyere.pk", "women"),
    FeedBrand("jeem", "Jeem", "https://jeem.pk", "women"),
    FeedBrand("tena-durrani", "Tena Durrani", "https://tenadurrani.com", "women"),
    FeedBrand("zara-shahjahan", "Zara Shahjahan", "https://zarashahjahan.com", "women"),
    FeedBrand("ammara-khan", "Ammara Khan", "https://ammarakhan.com", "women"),
    FeedBrand("zainab-chottani", "Zainab Chottani", "https://zainabchottani.com", "women"),
    FeedBrand("republic-womenswear", "Republic Womenswear", "https://republicwomenswear.com", "women"),
    FeedBrand("elan", "Elan", "https://elan.pk", "women"),
    FeedBrand("afrozeh", "Afrozeh", "https://afrozeh.com", "women"),
    FeedBrand("gulaal", "Gulaal", "https://gulaal.pk", "women"),
    FeedBrand("qalamkar", "Qalamkar", "https://qalamkar.com.pk", "women"),
    FeedBrand("alizeh", "Alizeh", "https://alizehofficial.com", "women"),
    FeedBrand("nureh", "Nureh", "https://nureh.pk", "women"),
    FeedBrand("ramsha", "Ramsha", "https://ramsha.pk", "women"),
    FeedBrand("taana-baana", "Taana Baana", "https://taanabaana.pk", "women"),
    FeedBrand("zubaidas", "Zubaidas", "https://zubaidas.com", "women"),
    FeedBrand("kross-kulture", "Kross Kulture", "https://krosskulture.com", "women"),
)

BY_KEY: dict[str, FeedBrand] = {b.key: b for b in FEED_BRANDS}

# Retailers whose products come in through the manual CSV import (no feed).
MANUAL_BRANDS: dict[str, str] = {"breakout": "Breakout"}


def brand_name(key: str) -> str:
    """Display name for a catalog `retailer` key."""
    if key in BY_KEY:
        return BY_KEY[key].name
    return MANUAL_BRANDS.get(key, key.replace("-", " ").title())
