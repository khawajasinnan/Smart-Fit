import sys
import os

# Add backend directory to path
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from services.brands import PAKISTANI_BRANDS

def test_new_brands_existence():
    print("=== Testing Brand Configuration Registration ===")
    names = {brand.name for brand in PAKISTANI_BRANDS}
    new_expected = {
        "Uniworth", "Rici Melion", "Sana Safinaz", "Maria.B", "Kayseria", 
        "Alkaram Studio", "Cross Stitch", "Zaha"
    }
    
    for brand in new_expected:
        assert brand in names, f"Brand {brand} must be registered in PAKISTANI_BRANDS"
        print(f"Verified Brand Registered: {brand}")
    
    assert "Daraz" not in names, "Daraz must not be used by SmartFit scraping"
    
    uniworth = next(b for b in PAKISTANI_BRANDS if b.name == "Uniworth")
    assert uniworth.html_only is False, "Uniworth should have Shopify-JSON enabled"
    
    # Verify Cambridge slugs
    cambridge = next(b for b in PAKISTANI_BRANDS if b.name == "Cambridge")
    assert "formal-suits" in cambridge.collection_slugs["male"], "Cambridge male slugs should contain formal-suits"
    assert "men-suits" not in cambridge.collection_slugs["male"], "Cambridge male slugs should not contain men-suits"
    
    # Verify Charcoal canonical base URL
    charcoal = next(b for b in PAKISTANI_BRANDS if b.name == "Charcoal")
    assert charcoal.base_url == "https://www.charcoal.com.pk", "Charcoal should use canonical domain"
    
    print("SUCCESS: Brand configurations verified!\n")

def test_suiting_category_matching():
    print("=== Testing Plain Suit / Tuxedo Category Matching ===")
    from services.query_builder import product_matches_category, product_conflicts_with_category
    
    # "M Grey Plain Classic Fit Suit" from Uniworth
    assert product_matches_category(
        "M Grey Plain Classic Fit Suit", [], None, "two-piece-suit"
    ) is True, "Plain suit should match two-piece-suit category"
    
    assert product_conflicts_with_category(
        "M Grey Plain Classic Fit Suit", [], "two-piece-suit"
    ) is False, "Plain suit should not conflict with two-piece-suit category"
    
    # "Black Plain Tuxedo Suit" from Charcoal
    assert product_matches_category(
        "Black Plain Tuxedo Suit", [], None, "two-piece-suit"
    ) is True, "Tuxedo suit should match two-piece-suit"
    
    assert product_conflicts_with_category(
        "Black Plain Tuxedo Suit", [], "two-piece-suit"
    ) is False, "Tuxedo suit should not conflict with two-piece-suit"
    
    # Make sure traditional suits ARE conflicts / blocked
    assert product_conflicts_with_category(
        "Ladies Embroidered Printed Lawn Suit", [], "two-piece-suit"
    ) is True, "Ladies traditional lawn suit must conflict with western suiting"
    
    assert product_conflicts_with_category(
        "Men Cotton Kurta Suit", [], "two-piece-suit"
    ) is True, "Traditional kurta suit must conflict with western suiting"
    
    print("SUCCESS: Suiting category matching verified!\n")


def test_gender_garment_conflict():
    from services.query_builder import gender_garment_conflict
    
    # Female asking for male garments (pent coat, sherwani, etc.)
    res_female_pentcoat = gender_garment_conflict("female", "pent coat")
    assert res_female_pentcoat is not None
    assert res_female_pentcoat["conflict"] is True
    assert "Female" in res_female_pentcoat["message"]
    assert "pent coat" in res_female_pentcoat["message"]
    assert len(res_female_pentcoat["alternatives"]) > 0

    res_female_sherwani = gender_garment_conflict("female", "sherwani")
    assert res_female_sherwani is not None
    assert res_female_sherwani["conflict"] is True

    # Male asking for female garments (kurti, gharara, etc.)
    res_male_kurti = gender_garment_conflict("male", "kurti")
    assert res_male_kurti is not None
    assert res_male_kurti["conflict"] is True
    assert "Male" in res_male_kurti["message"]
    assert "kurti" in res_male_kurti["message"]

    # Non-conflicting combinations
    assert gender_garment_conflict("female", "lawn suit") is None
    assert gender_garment_conflict("female", "kurti") is None
    assert gender_garment_conflict("male", "pent coat") is None
    assert gender_garment_conflict("male", "shalwar kameez") is None


def test_female_brand_expansion():
    brand_names = {b.name for b in PAKISTANI_BRANDS}
    new_female_brands = [
        "Asim Jofa", "Mushq", "Baroque", "Crimson", "Mohagni", 
        "Firdous", "So Kamal", "Maryam Hussain", "Saya", "Warda", 
        "Serene", "Ittehad", "Faraz Manan", "Minnie Minors"
    ]
    for b in new_female_brands:
        assert b in brand_names, f"Brand {b} must be registered in PAKISTANI_BRANDS"


def test_cv_gender_estimation_schema_and_logic():
    from models.cv_schemas import CvAnalysisResponse, BodyProportions
    from services.cv_analysis import _estimate_gender_from_pose
    
    # Test schema serialization
    resp = CvAnalysisResponse(
        body_shape="Hourglass",
        body_shape_confidence=0.85,
        estimated_size="M",
        landmarks=[],
        estimated_gender="female",
        gender_confidence=0.82,
    )
    assert resp.estimated_gender == "female"
    assert resp.gender_confidence == 0.82

    # Test proportion logic: Male with wide shoulders
    male_props = BodyProportions(
        shoulder_width_ratio=1.28,
        torso_length_ratio=0.45,
        leg_length_ratio=0.52,
        waist_hip_ratio=0.92,
    )
    gender_m, conf_m = _estimate_gender_from_pose(male_props)
    assert gender_m == "male"
    assert conf_m >= 0.7

    # Test proportion logic: Female with wider hips
    female_props = BodyProportions(
        shoulder_width_ratio=0.85,
        torso_length_ratio=0.43,
        leg_length_ratio=0.51,
        waist_hip_ratio=0.74,
    )
    gender_f, conf_f = _estimate_gender_from_pose(female_props)
    assert gender_f == "female"
    assert conf_f >= 0.7


if __name__ == "__main__":
    test_new_brands_existence()
    test_suiting_category_matching()
    test_gender_garment_conflict()
    test_female_brand_expansion()
    test_cv_gender_estimation_schema_and_logic()
    print("ALL TESTS PASSED SUCCESSFULLY!")
