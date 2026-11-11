from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app, get_version

client = TestClient(app)


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_root():
    r = client.get("/")
    assert r.status_code == 200
    assert "FastAPI Cloud Microservice" in r.text


def test_version():
    r = client.get("/version")
    assert r.status_code == 200
    assert "version" in r.json()


def test_get_version_env_var():
    with patch.dict("os.environ", {"APP_VERSION": "v2.0.0"}):
        assert get_version() == "v2.0.0"


def test_get_version_fallback():
    with patch.dict("os.environ", {}, clear=True), patch("shutil.which", return_value=None):
        assert get_version() == "dev"


def test_get_version_exception():
    with (
        patch.dict("os.environ", {}, clear=True),
        patch("shutil.which", side_effect=RuntimeError("simulated error")),
    ):
        assert get_version() == "dev"
