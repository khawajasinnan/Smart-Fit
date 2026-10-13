"""Curated Pakistani outfit fallbacks — used when live scraping yields few results.

RULES:
- NO stock/Unsplash images — image_url is null (better no image than wrong image)
- ALL product URLs point to real product pages or accurate collection pages
- STRICT category tags so only relevant items pass the category filter
- Covers all major Pakistani outfit types for men and women
"""

from __future__ import annotations

import uuid

from models.schemas import UserProfileInput
from services.query_builder import (
    product_conflicts_with_category,
    product_matches_category,
)


CATALOG: list[dict] = [
    # ════════════════════════════════════════════════════════════════
    # NEWLY CURATED PAKISTANI PREMIUM RANGE
    # ════════════════════════════════════════════════════════════════
    {
        "brand": "Cambridge",
        "title": "Black Slim Fit Two-Piece Suit (Pent Coat)",
        "category": "two-piece-suit",
        "price_pkr": 13990,
        "image_url": None,
        "product_url": "https://thecambridgeshop.com/collections/formal-suits",
        "sizes": ["38", "40", "42", "44", "46"],
        "colors": ["black"],
        "tags": ["male", "suit", "pent coat", "two piece", "formal", "office", "black", "wedding"],
    },
    {
        "brand": "Royal Tag",
        "title": "Classic Black Two-Piece Pent Coat",
        "category": "two-piece-suit",
        "price_pkr": 11990,
        "image_url": None,
        "product_url": "https://royaltag.pk/collections/suits",
        "sizes": ["38", "40", "42", "44"],
        "colors": ["black"],
        "tags": ["male", "suit", "pent coat", "two piece", "formal", "black", "wedding"],
    },
    {
        "brand": "Royal Tag",
        "title": "Budget Black Two-Piece Pent Coat",
        "category": "two-piece-suit",
        "price_pkr": 9990,
        "image_url": None,
        "product_url": "https://royaltag.pk/collections/suits",
        "sizes": ["38", "40", "42", "44"],
        "colors": ["black"],
        "tags": ["male", "suit", "pent coat", "two piece", "formal", "black", "interview", "office"],
    },
    {
        "brand": "Charcoal",
        "title": "Budget Blue Two-Piece Pent Coat",
        "category": "two-piece-suit",
        "price_pkr": 9990,
        "image_url": None,
        "product_url": "https://www.charcoal.com.pk/collections/suiting",
        "sizes": ["38", "40", "42", "44"],
        "colors": ["blue", "navy"],
        "tags": ["male", "suit", "pent coat", "two piece", "formal", "blue", "navy", "interview", "office"],
    },
    {
        "brand": "Charcoal",
        "title": "Charcoal Two-Piece Pent Coat Suit",
        "category": "two-piece-suit",
        "price_pkr": 11500,
        "image_url": None,
        "product_url": "https://www.charcoal.com.pk/collections/suiting",
        "sizes": ["38", "40", "42", "44", "46"],
        "colors": ["charcoal", "grey"],
        "tags": ["male", "suit", "pent coat", "two piece", "formal", "charcoal", "wedding"],
    },
    {
        "brand": "Cambridge",
        "title": "Budget Navy Two-Piece Pent Coat",
        "category": "two-piece-suit",
        "price_pkr": 10990,
        "image_url": None,
        "product_url": "https://thecambridgeshop.com/collections/formal-suits",
        "sizes": ["38", "40", "42", "44"],
        "colors": ["navy", "blue"],
        "tags": ["male", "suit", "pent coat", "two piece", "formal", "navy", "wedding"],
    },
    {
        "brand": "Royal Tag",
        "title": "Royal Blue Two-Piece Suit (Pent Coat)",
        "category": "two-piece-suit",
        "price_pkr": 14500,
        "image_url": None,
        "product_url": "https://royaltag.pk/collections/suits",
        "sizes": ["38", "40", "42", "44"],
        "colors": ["blue", "royal blue"],
        "tags": ["male", "suit", "pent coat", "two piece", "formal", "blue", "royal blue", "wedding"],
    },
    {
        "brand": "Charcoal",
        "title": "Navy Blue Two-Piece Suit (Pent Coat)",
        "category": "two-piece-suit",
        "price_pkr": 12990,
        "image_url": None,
        "product_url": "https://www.charcoal.com.pk/collections/suiting",
        "sizes": ["38", "40", "42", "44", "46"],
        "colors": ["blue", "navy"],
        "tags": ["male", "suit", "pent coat", "two piece", "formal", "blue", "navy", "office"],
    },
    {
        "brand": "Uniworth",
        "title": "Royal Blue Slim Fit Two-Piece Suit (Pent Coat)",
        "category": "two-piece-suit",
        "price_pkr": 24990,
        "image_url": None,
        "product_url": "https://uniworthshop.com/collections/suiting",
        "sizes": ["38", "40", "42", "44", "46"],
        "colors": ["blue", "royal blue"],
        "tags": ["male", "suit", "pent coat", "two piece", "formal", "blue", "royal blue", "wedding"],
    },
    {
        "brand": "Uniworth",
        "title": "Premium Black Sherwani – Wedding Wear",
        "category": "sherwani",
        "price_pkr": 19990,
        "image_url": None,
        "product_url": "https://uniworthshop.com/collections/ethnic-wear",
        "sizes": ["38", "40", "42", "44"],
        "colors": ["black"],
        "tags": ["male", "sherwani", "wedding", "baraat", "formal", "black", "groom"],
    },
    {
        "brand": "Rici Melion",
        "title": "Ivory White Sherwani – Royal Collection",
        "category": "sherwani",
        "price_pkr": 29990,
        "image_url": None,
        "product_url": "https://ricimelion.com/collections/sherwani",
        "sizes": ["38", "40", "42", "44"],
        "colors": ["white", "ivory"],
        "tags": ["male", "sherwani", "wedding", "nikah", "formal", "white", "ivory", "groom"],
    },
    {
        "brand": "Junaid Jamshed",
        "title": "Black Wash-and-Wear Shalwar Kameez Suit",
        "category": "shalwar-kameez",
        "price_pkr": 4790,
        "image_url": None,
        "product_url": "https://www.junaidjamshed.com/collections/men-kurta",
        "sizes": ["S", "M", "L", "XL", "XXL"],
        "colors": ["black"],
        "tags": ["male", "shalwar", "kameez", "formal", "eid", "black", "wash-and-wear"],
    },
    {
        "brand": "Sana Safinaz",
        "title": "Printed Lawn 3-Piece – Sapphire Blue",
        "category": "lawn-suit",
        "price_pkr": 5690,
        "image_url": None,
        "product_url": "https://www.sanasafinaz.com/collections/ready-to-wear",
        "sizes": ["XS", "S", "M", "L", "XL"],
        "colors": ["blue", "sky blue"],
        "tags": ["female", "lawn suit", "three piece", "dupatta", "blue", "pret"],
    },
    {
        "brand": "Maria.B",
        "title": "Embroidered Luxury Lawn Pret – Ruby Red",
        "category": "pret",
        "price_pkr": 8990,
        "image_url": None,
        "product_url": "https://www.mariab.pk/collections/ready-to-wear",
        "sizes": ["XS", "S", "M", "L", "XL"],
        "colors": ["red", "ruby red"],
        "tags": ["female", "pret", "ready to wear", "formal", "red", "embroidered"],
    },
    {
        "brand": "Kayseria",
        "title": "Classic Cotton Kurti – Rose Pink",
        "category": "kurti",
        "price_pkr": 2890,
        "image_url": None,
        "product_url": "https://www.kayseria.com/collections/ready-to-wear",
        "sizes": ["XS", "S", "M", "L", "XL"],
        "colors": ["pink", "rose pink"],
        "tags": ["female", "kurti", "cotton", "casual", "pink", "printed"],
    },
    {
        "brand": "Royal Tag",
        "title": "Smart-Casual Navy Blazer",
        "category": "blazer",
        "price_pkr": 6990,
        "image_url": None,
        "product_url": "https://royaltag.pk/collections/blazers",
        "sizes": ["38", "40", "42", "44", "46"],
        "colors": ["blue", "navy"],
        "tags": ["male", "blazer", "formal", "navy", "blue", "office", "casual"],
    },
    {
        "brand": "Uniworth",
        "title": "Formal Dress Shirt – Premium Black",
        "category": "formal-shirt",
        "price_pkr": 3490,
        "image_url": None,
        "product_url": "https://uniworthshop.com/collections/shirts",
        "sizes": ["S", "M", "L", "XL", "XXL"],
        "colors": ["black"],
        "tags": ["male", "formal shirt", "dress shirt", "black", "office"],
    },
    # ════════════════════════════════════════════════════════════════
    # MEN — EASTERN / TRADITIONAL
    # ════════════════════════════════════════════════════════════════
    {
        "brand": "Junaid Jamshed",
        "title": "Premium Wash & Wear Shalwar Kameez – Blue",
        "category": "shalwar-kameez",
        "price_pkr": 4990,
        "image_url": None,
        "product_url": "https://www.junaidjamshed.com/collections/men-kurta",
        "sizes": ["S", "M", "L", "XL", "XXL"],
        "colors": ["blue"],
        "tags": ["male", "shalwar", "kameez", "formal", "eid", "nikah", "wash-and-wear"],
    },
    {
        "brand": "Almirah",
        "title": "White Cotton Kurta Pajama Set – Nikah Collection",
        "category": "kurta",
        "price_pkr": 5990,
        "image_url": None,
        "product_url": "https://www.almirah.com.pk/collections/men-kurta",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["white", "cream"],
        "tags": ["male", "kurta", "pajama", "nikah", "wedding", "formal"],
    },
    {
        "brand": "Edenrobe",
        "title": "Embroidered Kurta Shalwar with Waistcoat – Black",
        "category": "waistcoat",
        "price_pkr": 8990,
        "image_url": None,
        "product_url": "https://edenrobe.com/collections/men-waistcoat",
        "sizes": ["S", "M", "L", "XL", "XXL"],
        "colors": ["black"],
        "tags": ["male", "kurta", "waistcoat", "shalwar", "wedding", "baraat", "formal"],
    },
    {
        "brand": "Muraqsh Man",
        "title": "Hand-Embroidered Kurta Waistcoat Set – Maroon",
        "category": "waistcoat",
        "price_pkr": 12990,
        "image_url": None,
        "product_url": "https://www.muraqshman.com/collections/kurta-waistcoat-set",
        "sizes": ["S", "M", "L", "XL", "XXL"],
        "colors": ["maroon"],
        "tags": ["male", "kurta", "waistcoat", "wedding", "mehndi", "baraat", "formal"],
    },
    {
        "brand": "LAAM",
        "title": "Luxury Sherwani with Churidar – Cream/Gold",
        "category": "sherwani",
        "price_pkr": 24000,
        "image_url": None,
        "product_url": "https://laam.pk/collections/men",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["cream", "gold"],
        "tags": ["male", "sherwani", "wedding", "baraat", "formal", "groom"],
    },
    {
        "brand": "Junaid Jamshed",
        "title": "Prince Coat – Navy Blue Velvet",
        "category": "prince-coat",
        "price_pkr": 15990,
        "image_url": None,
        "product_url": "https://www.junaidjamshed.com/collections/men-waistcoat",
        "sizes": ["M", "L", "XL", "XXL"],
        "colors": ["navy", "blue"],
        "tags": ["male", "prince coat", "achkan", "wedding", "baraat", "formal"],
    },
    # ════════════════════════════════════════════════════════════════
    # MEN — WESTERN / FORMAL
    # ════════════════════════════════════════════════════════════════
    {
        "brand": "Cambridge",
        "title": "Navy Blue Two-Piece Pent Coat – Slim Fit",
        "category": "two-piece-suit",
        "price_pkr": 14990,
        "image_url": None,
        "product_url": "https://thecambridgeshop.com/collections/formal-suits",
        "sizes": ["S", "M", "L", "XL", "XXL"],
        "colors": ["navy", "blue"],
        "tags": ["male", "suit", "pent coat", "two piece", "blazer", "formal", "office", "wedding"],
    },
    {
        "brand": "Cambridge",
        "title": "Charcoal Grey Three-Piece Suit – Classic Fit",
        "category": "three-piece-suit",
        "price_pkr": 19990,
        "image_url": None,
        "product_url": "https://thecambridgeshop.com/collections/formal-suits",
        "sizes": ["M", "L", "XL", "XXL"],
        "colors": ["charcoal", "grey"],
        "tags": ["male", "suit", "three piece", "blazer", "formal", "office", "walima"],
    },
    {
        "brand": "Outfitters",
        "title": "Slim Fit Blazer – Black",
        "category": "blazer",
        "price_pkr": 7990,
        "image_url": None,
        "product_url": "https://outfitters.com.pk/collections/men-jackets",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["black"],
        "tags": ["male", "blazer", "formal", "office", "party"],
    },
    {
        "brand": "Cambridge",
        "title": "White Oxford Formal Shirt – Slim Fit",
        "category": "formal-shirt",
        "price_pkr": 3490,
        "image_url": None,
        "product_url": "https://thecambridgeshop.com/collections/formal-shirts",
        "sizes": ["S", "M", "L", "XL", "XXL"],
        "colors": ["white"],
        "tags": ["male", "formal shirt", "dress shirt", "office"],
    },
    {
        "brand": "Outfitters",
        "title": "Casual Check Shirt – Blue/White",
        "category": "casual-shirt",
        "price_pkr": 2990,
        "image_url": None,
        "product_url": "https://outfitters.com.pk/collections/men-shirts",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["blue", "white"],
        "tags": ["male", "shirt", "casual shirt", "casual"],
    },
    {
        "brand": "Breakout",
        "title": "Relaxed Fit Polo Shirt – Olive",
        "category": "polo-shirt",
        "price_pkr": 2490,
        "image_url": None,
        "product_url": "https://www.breakout.com.pk/collections/men",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["olive"],
        "tags": ["male", "polo", "casual"],
    },
    {
        "brand": "Outfitters",
        "title": "Graphic T-Shirt – Black",
        "category": "t-shirt",
        "price_pkr": 1490,
        "image_url": None,
        "product_url": "https://outfitters.com.pk/collections/men-new-arrivals",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["black"],
        "tags": ["male", "female", "t-shirt", "tee", "casual", "streetwear"],
    },
    {
        "brand": "Outfitters",
        "title": "Slim Fit Chinos – Khaki",
        "category": "chinos",
        "price_pkr": 3290,
        "image_url": None,
        "product_url": "https://outfitters.com.pk/collections/men-jeans",
        "sizes": ["30", "32", "34", "36", "38"],
        "colors": ["khaki"],
        "tags": ["male", "chinos", "trouser", "casual", "office"],
    },
    {
        "brand": "Breakout",
        "title": "Stretch Denim Jeans – Dark Blue",
        "category": "jeans",
        "price_pkr": 3990,
        "image_url": None,
        "product_url": "https://www.breakout.com.pk/collections/men",
        "sizes": ["30", "32", "34", "36"],
        "colors": ["blue"],
        "tags": ["male", "jeans", "denim", "casual"],
    },
    {
        "brand": "Outfitters",
        "title": "Hooded Jacket – Military Green",
        "category": "jacket",
        "price_pkr": 5490,
        "image_url": None,
        "product_url": "https://outfitters.com.pk/collections/men-jackets",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["green"],
        "tags": ["male", "jacket", "casual", "winter"],
    },
    # ════════════════════════════════════════════════════════════════
    # WOMEN — EASTERN / TRADITIONAL
    # ════════════════════════════════════════════════════════════════
    {
        "brand": "Khaadi",
        "title": "Embroidered Lawn Kurti – Green",
        "category": "kurti",
        "price_pkr": 3490,
        "image_url": None,
        "product_url": "https://www.khaadi.com/ready-to-wear",
        "sizes": ["XS", "S", "M", "L", "XL"],
        "colors": ["green"],
        "tags": ["female", "kurti", "lawn", "casual", "eid"],
    },
    {
        "brand": "Sapphire",
        "title": "Three-Piece Printed Lawn Suit – Pink",
        "category": "ladies-three-piece",
        "price_pkr": 5490,
        "image_url": None,
        "product_url": "https://pk.sapphireonline.pk/collections/ready-to-wear",
        "sizes": ["XS", "S", "M", "L", "XL"],
        "colors": ["pink"],
        "tags": ["female", "lawn suit", "three piece", "dupatta", "eid", "casual"],
    },
    {
        "brand": "Sapphire",
        "title": "Stitched Ready-to-Wear Lawn Suit – Pink",
        "category": "pret",
        "price_pkr": 6490,
        "image_url": None,
        "product_url": "https://pk.sapphireonline.pk/collections/ready-to-wear",
        "sizes": ["XS", "S", "M", "L", "XL"],
        "colors": ["pink"],
        "tags": ["female", "stitched", "ready to wear", "pret", "lawn suit", "three piece"],
    },
    {
        "brand": "Sapphire",
        "title": "Unstitched Lawn 3-Piece Suit – Blue",
        "category": "unstitched",
        "price_pkr": 5990,
        "image_url": None,
        "product_url": "https://pk.sapphireonline.pk/collections/unstitched",
        "sizes": ["Unstitched"],
        "colors": ["blue"],
        "tags": ["female", "unstitched", "lawn", "fabric", "three piece", "blue"],
    },
    {
        "brand": "Limelight",
        "title": "Stitched Pret Kurta – Maroon",
        "category": "pret",
        "price_pkr": 2990,
        "image_url": None,
        "product_url": "https://www.limelight.pk/collections/ready-to-wear",
        "sizes": ["XS", "S", "M", "L", "XL"],
        "colors": ["maroon"],
        "tags": ["female", "pret", "ready to wear", "kurti", "casual"],
    },
    {
        "brand": "Ideas",
        "title": "Unstitched Lawn 3-Piece – Floral Blue",
        "category": "unstitched",
        "price_pkr": 4990,
        "image_url": None,
        "product_url": "https://www.gulahmedshop.com/collections/women-unstitched",
        "sizes": ["Unstitched"],
        "colors": ["blue"],
        "tags": ["female", "unstitched", "lawn", "fabric", "three piece"],
    },
    {
        "brand": "Ethnic",
        "title": "Luxury Party Wear Dress – Gold Embroidered",
        "category": "ladies-formal",
        "price_pkr": 12990,
        "image_url": None,
        "product_url": "https://ethnic.pk/collections/formal",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["gold"],
        "tags": ["female", "formal", "party wear", "luxury pret", "wedding"],
    },
    {
        "brand": "Maria B",
        "title": "Bridal Lehenga Set – Red/Gold",
        "category": "bridal",
        "price_pkr": 89990,
        "image_url": None,
        "product_url": "https://www.mariab.pk/collections/bridal",
        "sizes": ["S", "M", "L"],
        "colors": ["red", "gold"],
        "tags": ["female", "bridal", "lehenga", "wedding", "dulhan"],
    },
    {
        "brand": "Khaadi",
        "title": "Embroidered Gharara Set – Teal",
        "category": "gharara",
        "price_pkr": 9990,
        "image_url": None,
        "product_url": "https://www.khaadi.com/ready-to-wear",
        "sizes": ["XS", "S", "M", "L"],
        "colors": ["teal"],
        "tags": ["female", "gharara", "mehndi", "wedding", "formal"],
    },
    {
        "brand": "Sapphire",
        "title": "Printed Sharara Set with Dupatta – Mustard",
        "category": "sharara",
        "price_pkr": 7490,
        "image_url": None,
        "product_url": "https://pk.sapphireonline.pk/collections/ready-to-wear",
        "sizes": ["XS", "S", "M", "L", "XL"],
        "colors": ["mustard"],
        "tags": ["female", "sharara", "dupatta", "mehndi", "eid"],
    },
    {
        "brand": "Bonanza Satrangi",
        "title": "Anarkali Frock – Pastel Pink",
        "category": "anarkali",
        "price_pkr": 6490,
        "image_url": None,
        "product_url": "https://www.bonanzasatrangi.com/collections/pret",
        "sizes": ["XS", "S", "M", "L", "XL"],
        "colors": ["pink", "pastel"],
        "tags": ["female", "anarkali", "frock", "formal", "party"],
    },
    {
        "brand": "Almirah",
        "title": "Silk Maxi Dress – Burgundy",
        "category": "maxi-dress",
        "price_pkr": 8990,
        "image_url": None,
        "product_url": "https://www.almirah.com.pk/collections/women-ready-to-wear",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["burgundy"],
        "tags": ["female", "maxi", "maxi dress", "gown", "formal", "walima"],
    },
    {
        "brand": "Limelight",
        "title": "Cotton Abaya – Black",
        "category": "abaya",
        "price_pkr": 3990,
        "image_url": None,
        "product_url": "https://www.limelight.pk/collections/ready-to-wear",
        "sizes": ["Free Size"],
        "colors": ["black"],
        "tags": ["female", "abaya", "modest", "casual"],
    },
    {
        "brand": "Khaadi",
        "title": "Embroidered Pashmina Shawl – Cream",
        "category": "shawl",
        "price_pkr": 4490,
        "image_url": None,
        "product_url": "https://www.khaadi.com/ready-to-wear",
        "sizes": ["Free Size"],
        "colors": ["cream"],
        "tags": ["female", "shawl", "pashmina", "winter", "formal"],
    },
    # ════════════════════════════════════════════════════════════════
    # WOMEN — WESTERN / CASUAL
    # ════════════════════════════════════════════════════════════════
    {
        "brand": "Outfitters",
        "title": "Relaxed Fit T-Shirt – White",
        "category": "t-shirt",
        "price_pkr": 1290,
        "image_url": None,
        "product_url": "https://outfitters.com.pk/collections/women-tops",
        "sizes": ["XS", "S", "M", "L"],
        "colors": ["white"],
        "tags": ["female", "t-shirt", "tee", "casual", "streetwear"],
    },
    {
        "brand": "Breakout",
        "title": "High-Waist Skinny Jeans – Black",
        "category": "jeans",
        "price_pkr": 3490,
        "image_url": None,
        "product_url": "https://www.breakout.com.pk/collections/women",
        "sizes": ["26", "28", "30", "32"],
        "colors": ["black"],
        "tags": ["female", "jeans", "denim", "black", "skinny", "casual", "western"],
    },
    {
        "brand": "Asim Jofa",
        "title": "Luxury Chiffon Embroidered Suit – Red",
        "category": "ladies-formal",
        "price_pkr": 14500,
        "image_url": None,
        "product_url": "https://asimjofa.com/collections/luxury-pret",
        "sizes": ["S", "M", "L"],
        "colors": ["red"],
        "tags": ["female", "luxury pret", "formal", "party wear", "red", "chiffon", "embroidered"],
    },
    {
        "brand": "Asim Jofa",
        "title": "Bridal Velvet Lehenga Set – Deep Maroon",
        "category": "bridal",
        "price_pkr": 45000,
        "image_url": None,
        "product_url": "https://asimjofa.com/collections/bridal",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["maroon"],
        "tags": ["female", "bridal", "lehenga", "velvet", "maroon", "wedding", "baraat"],
    },
    {
        "brand": "Mushq",
        "title": "Festive Organza Suit – Gold",
        "category": "ladies-formal",
        "price_pkr": 18900,
        "image_url": None,
        "product_url": "https://mushq.pk/collections/festive",
        "sizes": ["XS", "S", "M", "L"],
        "colors": ["gold"],
        "tags": ["female", "luxury pret", "formal", "gold", "organza", "party wear", "mehndi"],
    },
    {
        "brand": "Baroque",
        "title": "Velvet Embroidered Maxi – Navy Blue",
        "category": "maxi-dress",
        "price_pkr": 21500,
        "image_url": None,
        "product_url": "https://baroque.pk/collections/velvet",
        "sizes": ["S", "M", "L"],
        "colors": ["navy", "blue"],
        "tags": ["female", "maxi dress", "velvet", "navy", "formal", "winter", "wedding"],
    },
    {
        "brand": "Crimson",
        "title": "Luxury Lawn 3-Piece Set – Peach",
        "category": "lawn-suit",
        "price_pkr": 12900,
        "image_url": None,
        "product_url": "https://crimson.com.pk/collections/luxury-lawn",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["peach"],
        "tags": ["female", "lawn suit", "luxury pret", "peach", "three piece", "printed", "embroidered"],
    },
    {
        "brand": "Mohagni",
        "title": "Casual Printed Lawn Kurti – Yellow",
        "category": "kurti",
        "price_pkr": 3200,
        "image_url": None,
        "product_url": "https://mohagni.com/collections/pret",
        "sizes": ["XS", "S", "M", "L", "XL"],
        "colors": ["yellow"],
        "tags": ["female", "kurti", "lawn", "yellow", "casual", "printed"],
    },
    {
        "brand": "Firdous",
        "title": "Unstitched Cotton Suit – White & Blue",
        "category": "unstitched",
        "price_pkr": 4500,
        "image_url": None,
        "product_url": "https://firdous.com/collections/unstitched",
        "sizes": ["Unstitched"],
        "colors": ["white", "blue"],
        "tags": ["female", "unstitched", "cotton", "white", "blue", "casual", "summer"],
    },
    {
        "brand": "So Kamal",
        "title": "Khaddar Winter Pret Shirt – Rust",
        "category": "kurti",
        "price_pkr": 3800,
        "image_url": None,
        "product_url": "https://sokamal.com/collections/winter",
        "sizes": ["S", "M", "L"],
        "colors": ["rust", "orange"],
        "tags": ["female", "kurti", "khaddar", "rust", "winter", "casual"],
    },
    {
        "brand": "Maryam Hussain",
        "title": "Bridal Walima Gown – Silver Grey",
        "category": "bridal",
        "price_pkr": 65000,
        "image_url": None,
        "product_url": "https://maryamhussain.com/collections/bridal",
        "sizes": ["S", "M", "L"],
        "colors": ["silver", "grey"],
        "tags": ["female", "bridal", "gown", "maxi dress", "silver", "grey", "walima", "wedding"],
    },
    {
        "brand": "Saya",
        "title": "Western Denim Co-ord Set – Light Blue",
        "category": "coord-set",
        "price_pkr": 5500,
        "image_url": None,
        "product_url": "https://sfrapparel.com/collections/western",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["blue", "light blue"],
        "tags": ["female", "co-ord set", "western", "denim", "blue", "casual"],
    },
    {
        "brand": "Warda",
        "title": "Linen Printed 2-Piece Suit – Olive Green",
        "category": "ladies-two-piece",
        "price_pkr": 4200,
        "image_url": None,
        "product_url": "https://wfrapparel.com/collections/winter",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["olive", "green"],
        "tags": ["female", "two piece", "linen", "olive", "green", "winter", "casual"],
    },
    {
        "brand": "Serene",
        "title": "Premium Chiffon Formal Suit – Black",
        "category": "ladies-formal",
        "price_pkr": 16500,
        "image_url": None,
        "product_url": "https://serenepremium.com/collections/pret",
        "sizes": ["XS", "S", "M", "L"],
        "colors": ["black"],
        "tags": ["female", "luxury pret", "formal", "black", "chiffon", "party wear"],
    },
    {
        "brand": "Ittehad",
        "title": "Unstitched Winter Karandi Suit – Purple",
        "category": "unstitched",
        "price_pkr": 5200,
        "image_url": None,
        "product_url": "https://ittehadtextiles.com/collections/winter",
        "sizes": ["Unstitched"],
        "colors": ["purple"],
        "tags": ["female", "unstitched", "karandi", "purple", "winter", "casual"],
    },
    {
        "brand": "Faraz Manan",
        "title": "Couture Bridal Lehenga – Pastel Pink",
        "category": "bridal",
        "price_pkr": 150000,
        "image_url": None,
        "product_url": "https://farazmanan.com/bridal",
        "sizes": ["Custom"],
        "colors": ["pink", "pastel"],
        "tags": ["female", "bridal", "couture", "lehenga", "pink", "wedding"],
    },
    {
        "brand": "Minnie Minors",
        "title": "Women's Casual T-Shirt – White",
        "category": "t-shirt",
        "price_pkr": 1500,
        "image_url": None,
        "product_url": "https://minnieminors.com/collections/women",
        "sizes": ["S", "M", "L"],
        "colors": ["white"],
        "tags": ["female", "t-shirt", "western", "white", "casual"],
    },
    {
        "brand": "Minnie Minors",
        "title": "Women's Wide Leg Jeans – Blue",
        "category": "jeans",
        "price_pkr": 3500,
        "image_url": None,
        "product_url": "https://minnieminors.com/collections/women",
        "sizes": ["28", "30", "32", "34"],
        "colors": ["blue"],
        "tags": ["female", "jeans", "western", "blue", "casual"],
    },
    {
        "brand": "Asim Jofa",
        "title": "Embroidered Lawn Kurti – Mustard",
        "category": "kurti",
        "price_pkr": 4500,
        "image_url": None,
        "product_url": "https://asimjofa.com/collections/lawn",
        "sizes": ["S", "M", "L"],
        "colors": ["mustard", "yellow"],
        "tags": ["female", "kurti", "lawn", "mustard", "yellow", "casual"],
    },
    {
        "brand": "Mushq",
        "title": "Festive Velvet Gharara – Emerald Green",
        "category": "gharara",
        "price_pkr": 25000,
        "image_url": None,
        "product_url": "https://mushq.pk/collections/festive",
        "sizes": ["S", "M", "L"],
        "colors": ["emerald", "green"],
        "tags": ["female", "gharara", "velvet", "green", "emerald", "formal", "wedding"],
    },
    {
        "brand": "Baroque",
        "title": "Luxury Lawn Unstitched 3-Piece – Lilac",
        "category": "unstitched",
        "price_pkr": 11000,
        "image_url": None,
        "product_url": "https://baroque.pk/collections/unstitched",
        "sizes": ["Unstitched"],
        "colors": ["lilac", "purple"],
        "tags": ["female", "unstitched", "lawn", "three piece", "purple", "lilac"],
    },
    {
        "brand": "Saya",
        "title": "Casual Printed Lawn 2-Piece – Orange",
        "category": "ladies-two-piece",
        "price_pkr": 3500,
        "image_url": None,
        "product_url": "https://sfrapparel.com/collections/pret",
        "sizes": ["S", "M", "L", "XL"],
        "colors": ["orange"],
        "tags": ["female", "two piece", "lawn", "orange", "casual", "printed"],
    }
]


def local_products(
    profile: UserProfileInput,
    context: dict,
    limit: int,
) -> list[dict]:
    """Return curated items that match the requested category.

    Chat-requested color is a hard requirement. Profile colors remain a soft
    ranking signal in the scoring engine.
    """
    gender = context.get("gender", "unisex")
    exact_category = context.get("exact_category")
    budget_max = context.get("budget_max") or profile.budget_max
    requested_brands = {
        b.lower() for b in (context.get("requested_brands") or []) if isinstance(b, str)
    }
    requested_colors = {
        c.lower().strip()
        for c in (context.get("requested_colors") or [])
        if isinstance(c, str) and c.strip()
    }
    construction = context.get("construction")
    outfit_context = context.get("outfit_context")

    color_matched: list[dict] = []
    category_matched: list[dict] = []

    for item in CATALOG:
        tags = set(item["tags"])
        tag_text = " ".join(item["tags"]).lower()
        blob = f"{item['title']} {tag_text} {item.get('category') or ''}".lower()

        if requested_brands and item["brand"].lower() not in requested_brands:
            continue

        # Gender filter
        if gender != "unisex" and gender not in tags and "unisex" not in tags:
            continue

        if construction == "unstitched" and "unstitched" not in blob and "fabric" not in blob:
            continue
        if construction == "stitched" and ("unstitched" in blob or "fabric" in blob):
            continue

        if outfit_context == "shalwar-kameez-waistcoat":
            if not (
                ("waistcoat" in blob or "waist coat" in blob or "vest" in blob)
                and any(w in blob for w in ("shalwar", "salwar", "kameez", "qameez", "kurta"))
            ):
                continue

        # ── STRICT CATEGORY FILTER ──
        if exact_category:
            if not product_matches_category(
                item["title"], item["tags"], item.get("category"), exact_category
            ):
                continue
            if product_conflicts_with_category(item["title"], item["tags"], exact_category):
                continue

        # Budget filter (lenient)
        if budget_max and item.get("price_pkr") and item["price_pkr"] > budget_max * 1.5:
            continue

        item_colors = set(item.get("colors") or [])
        if requested_colors and not (requested_colors & item_colors):
            continue

        enriched = dict(item)
        enriched["id"] = str(uuid.uuid4())
        enriched["currency"] = "PKR"
        enriched["in_stock"] = True

        if requested_colors and (requested_colors & item_colors):
            color_matched.append(enriched)
        else:
            category_matched.append(enriched)

    # Return color-matched items first, then others
    results = color_matched + category_matched
    return results[:limit]
