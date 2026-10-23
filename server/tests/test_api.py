import json

from app.safety import COOKED_FALLBACK, UNCLEAR_SAY
from conftest import ASK_BODY, check_body, make_client


def test_health_reports_provider(client):
    body = client.get("/health").json()
    assert body["ok"] and body["configured"] and body["provider"] == "fake"


# /ask


def test_ask_returns_reply(client, fake_llm):
    fake_llm.next_reply = "About one to two centimetres wide is perfect."
    res = client.post("/ask", json=ASK_BODY)
    assert res.status_code == 200
    assert res.json() == {"reply": "About one to two centimetres wide is perfect."}


def test_ask_prompt_has_step_swaps_and_question(client, fake_llm):
    client.post("/ask", json=ASK_BODY)
    text = fake_llm.calls[0]["text"]
    assert "Cut half a cucumber" in text
    assert "Build your bowl" in text
    assert "salad-lemon-dressing" in text
    assert "How small is bite-sized?" in text


def test_ask_keeps_only_the_latest_history(client, fake_llm):
    history = [{"from": "user", "text": f"turn {i}"} for i in range(10)]
    client.post("/ask", json={**ASK_BODY, "history": history})
    text = fake_llm.calls[0]["text"]
    assert "turn 9" in text and "turn 4" in text and "turn 3" not in text


def test_ask_last_step_says_so(client, fake_llm):
    client.post("/ask", json={**ASK_BODY, "nextStepTitle": ""})
    assert "This is the last step." in fake_llm.calls[0]["text"]


def test_ask_strips_markdown_for_speech(client, fake_llm):
    fake_llm.next_reply = "**Tip:**\n- Use a sharp knife."
    assert client.post("/ask", json=ASK_BODY).json()["reply"] == "Tip: Use a sharp knife."


def test_ask_replaces_doneness_claims(client, fake_llm):
    fake_llm.next_reply = "Yes, the chicken is cooked through, go ahead."
    assert client.post("/ask", json=ASK_BODY).json()["reply"] == COOKED_FALLBACK


def test_ask_rejects_missing_fields(client):
    res = client.post("/ask", json={"sessionId": "x"})
    assert res.status_code == 400
    assert res.json()["error"].startswith("invalid request")


def test_ask_timeout_is_504(fake_llm):
    fake_llm.delay_s = 0.5
    client = make_client(fake_llm, ask_timeout_s=0.05)
    res = client.post("/ask", json=ASK_BODY)
    assert res.status_code == 504
    assert "error" in res.json()


def test_unconfigured_model_is_503():
    from fastapi.testclient import TestClient

    from app.config import Settings
    from app.main import create_app

    settings = Settings(_env_file=None, llm_provider="claude", anthropic_api_key="",
                        log_db_path=":memory:")
    client = TestClient(create_app(settings))
    res = client.post("/ask", json=ASK_BODY)
    assert res.status_code == 503
    assert "ANTHROPIC_API_KEY" in res.json()["error"]
    assert client.get("/health").json()["configured"] is False


# /check-step


def test_check_step_returns_status(client, fake_llm, jpeg_b64):
    fake_llm.next_reply = json.dumps({"status": "done", "say": "Those look bite-sized."})
    res = client.post("/check-step", json=check_body(jpeg_b64))
    assert res.status_code == 200
    assert res.json() == {"status": "done", "say": "Those look bite-sized."}
    assert fake_llm.calls[0]["has_image"]


def test_check_step_accepts_json_wrapped_in_text(client, fake_llm, jpeg_b64):
    fake_llm.next_reply = 'Here you go: ```json\n{"status": "not_yet", "say": "Keep chopping."}\n```'
    assert client.post("/check-step", json=check_body(jpeg_b64)).json()["status"] == "not_yet"


def test_check_step_malformed_answer_is_unsure(client, fake_llm, jpeg_b64):
    fake_llm.next_reply = "I think it looks great!"
    assert client.post("/check-step", json=check_body(jpeg_b64)).json() == {
        "status": "unsure",
        "say": UNCLEAR_SAY,
    }


def test_check_step_never_reports_cooked_meat_as_done(client, fake_llm, jpeg_b64):
    fake_llm.next_reply = json.dumps({"status": "done", "say": "The chicken is fully cooked through."})
    body = client.post("/check-step", json=check_body(jpeg_b64)).json()
    assert body == {"status": "unsure", "say": COOKED_FALLBACK}


def test_check_step_passes_the_users_question(client, fake_llm, jpeg_b64):
    client.post("/check-step", json={**check_body(jpeg_b64), "question": "Small enough?"})
    assert "Small enough?" in fake_llm.calls[0]["text"]


def test_check_step_rejects_non_image(client):
    res = client.post("/check-step", json=check_body("bm90IGFuIGltYWdl"))
    assert res.status_code == 400
    assert res.json() == {"error": "image is not a readable photo"}


def test_check_step_accepts_data_url(client, jpeg_b64):
    res = client.post("/check-step", json=check_body("data:image/jpeg;base64," + jpeg_b64))
    assert res.status_code == 200


def test_check_step_rejects_bad_source(client, jpeg_b64):
    res = client.post("/check-step", json={**check_body(jpeg_b64), "source": "drone"})
    assert res.status_code == 400


# /log and export


def test_log_stores_event(client):
    res = client.post(
        "/log",
        json={"sessionId": "a1", "type": "step_next", "time": "2026-10-28T14:03:12", "data": {"step": 2}},
    )
    assert res.json() == {"ok": True}
    assert client.app.state.store.count("events") == 1


def test_log_rejects_unknown_type(client):
    res = client.post("/log", json={"sessionId": "a1", "type": "dance", "data": {}})
    assert res.status_code == 400


def test_model_calls_are_timed(client):
    client.post("/ask", json=ASK_BODY)
    assert client.app.state.store.count("llm_calls") == 1


def test_export_is_off_without_admin_key(client):
    assert client.get("/export/events.csv").status_code == 404


def test_export_csv_with_admin_key(fake_llm):
    client = make_client(fake_llm, admin_key="secret")
    client.post("/log", json={"sessionId": "a1", "type": "pause", "data": {"step": 1}})
    assert client.get("/export/events.csv").status_code == 401
    res = client.get("/export/events.csv", headers={"X-Admin-Key": "secret"})
    assert res.status_code == 200
    assert "a1,pause" in res.text


# Optional shared key


def test_api_key_required_when_set(fake_llm):
    client = make_client(fake_llm, app_api_key="k1")
    assert client.post("/ask", json=ASK_BODY).status_code == 401
    assert client.post("/ask", json=ASK_BODY, headers={"X-API-Key": "k1"}).status_code == 200
    assert client.get("/health").status_code == 200
