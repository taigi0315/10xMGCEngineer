from fastapi.testclient import TestClient
from apps.api.main import app  # 리포지토리 루트 기준 모듈 임포트

client = TestClient(app)

def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}

def test_query_post():
    resp = client.post("/query", json={"text": "hello"})
    assert resp.status_code == 200
    assert resp.json()["received"] == "hello"

def test_query_get():
    resp = client.get("/query", params={"query": "world"})
    assert resp.status_code == 200
    assert resp.json()["received"] == "world"