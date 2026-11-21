"""Test-wide settings: keep tests offline and deterministic."""

import os

# Never download/load FashionCLIP during tests; tests inject a fake embedder.
os.environ.setdefault("FASHIONCLIP_AUTOLOAD", "false")
# Never start the scheduled catalog refresh (live store requests) in tests.
os.environ.setdefault("CATALOG_REFRESH_HOURS", "0")
# Never read stores through the cloud runner (Modal) in tests, whatever .env says;
# tests fake the stores locally. Tests of the cloud path set it themselves.
os.environ["SCRAPER_BACKEND"] = "local"
# Same for the try-on GPU: tests choose their backend explicitly.
os.environ["TRYON_BACKEND"] = ""
# Tests never write the real refresh schedule file.
os.environ["CATALOG_REFRESH_STATE_PATH"] = os.path.join(os.path.dirname(__file__), ".refresh_state_test.json")
# The rule-ranking tests check exact rule order; the learned models (spec
# §23.25) are tested on their own with models trained in a temp folder.
os.environ["LEARNED_RANKING_ENABLED"] = "false"
# Automatic retraining and impression logging never run against the real
# database in tests; the tests of §23.26 switch them on with fakes.
os.environ["AUTO_RETRAIN_HOURS"] = "0"
os.environ["IMPRESSION_LOGGING_ENABLED"] = "false"
# Hairstyle previews never call the Modal GPU in tests (spec §23.27); the
# GPU path is tested with a fake client.
os.environ["HAIRSTYLE_BACKEND"] = ""
