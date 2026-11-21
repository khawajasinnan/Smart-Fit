"""CV image loading safety (needs OpenCV + MediaPipe -> runs in Docker / CI)."""

import asyncio
import base64

import pytest

pytest.importorskip("cv2")
pytest.importorskip("mediapipe")

import cv2  # noqa: E402
import httpx  # noqa: E402
import numpy as np  # noqa: E402

from services.cv_analysis import pose  # noqa: E402
from shared.config import settings  # noqa: E402


def _jpeg(w: int, h: int) -> bytes:
    ok, buf = cv2.imencode(".jpg", np.full((h, w, 3), 128, dtype=np.uint8))
    assert ok
    return buf.tobytes()


def test_large_images_are_downscaled(monkeypatch):
    monkeypatch.setattr(settings, "cv_max_image_side", 800)
    img = pose.decode_image(_jpeg(2400, 1200))
    assert max(img.shape[:2]) == 800


def test_non_image_bytes_are_rejected():
    with pytest.raises(pose.ImageLoadError):
        pose.decode_image(b"definitely not a photo")


def test_base64_size_is_checked_before_decoding(monkeypatch):
    monkeypatch.setattr(settings, "cv_max_image_bytes", 100)
    with pytest.raises(pose.ImageLoadError, match="too large"):
        pose.load_image_from_base64(base64.b64encode(b"x" * 1000).decode())


def test_data_uri_prefix_is_accepted():
    data = "data:image/jpeg;base64," + base64.b64encode(_jpeg(40, 40)).decode()
    assert pose.load_image_from_base64(data).shape[:2] == (40, 40)


@pytest.mark.parametrize(
    ("url", "reason"),
    [
        ("http://example.supabase.co/a.jpg", "https"),
        ("https://evil.example.com/a.jpg", "SmartFit storage"),
        ("https://169.254.169.254/latest/meta-data", "SmartFit storage"),
    ],
)
def test_url_scheme_and_host_allow_list(monkeypatch, url, reason):
    monkeypatch.setattr(settings, "supabase_url", "https://example.supabase.co")
    monkeypatch.setattr(settings, "cv_allowed_image_hosts", "")
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(200)))
    with pytest.raises(pose.ImageLoadError, match=reason):
        asyncio.run(pose.load_image_from_url(client, url))


def test_allowed_url_downloads_and_redirects_are_not_followed(monkeypatch):
    monkeypatch.setattr(settings, "supabase_url", "https://example.supabase.co")
    good = _jpeg(30, 30)

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/redirect":
            return httpx.Response(302, headers={"location": "https://evil.example.com/x.jpg"})
        return httpx.Response(200, content=good, headers={"content-type": "image/jpeg"})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    img = asyncio.run(pose.load_image_from_url(client, "https://example.supabase.co/storage/a.jpg"))
    assert img.shape[:2] == (30, 30)
    with pytest.raises(pose.ImageLoadError):
        asyncio.run(pose.load_image_from_url(client, "https://example.supabase.co/redirect"))


def test_oversized_download_is_aborted(monkeypatch):
    monkeypatch.setattr(settings, "supabase_url", "https://example.supabase.co")
    monkeypatch.setattr(settings, "cv_max_image_bytes", 1000)
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(
            lambda r: httpx.Response(200, content=b"x" * 5000, headers={"content-type": "image/jpeg"})
        )
    )
    with pytest.raises(pose.ImageLoadError, match="too large"):
        asyncio.run(pose.load_image_from_url(client, "https://example.supabase.co/big.jpg"))


def test_model_loads_once_and_finds_no_body_in_blank_image():
    estimator = pose.PoseEstimator()
    try:
        landmarks, confidence = estimator.detect(cv2.imdecode(np.frombuffer(_jpeg(256, 256), np.uint8), 1))
        assert landmarks == [] and confidence == 0.0
    finally:
        estimator.close()
