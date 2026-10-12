from fastapi.testclient import TestClient

from app.main import app

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
