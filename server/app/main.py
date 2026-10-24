"""CookAlong backend: the only part of CookAlong that talks to the AI.

Endpoints follow docs/api.md. Run locally with:
    uvicorn app.main:app --reload
"""

import logging
import secrets
import time

from fastapi import Depends, FastAPI, Header, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse
from starlette.exceptions import HTTPException

from . import prompts, safety
from .config import Settings, get_settings
from .images import BadImage, prepare_jpeg
from .llm import LLM, LLMError, LLMNotConfigured, LLMTimeout, build_llm
from .schemas import (
    AskRequest,
    AskResponse,
    CheckStepRequest,
    CheckStepResponse,
    LogRequest,
    LogResponse,
)
from .storage import Store

log = logging.getLogger("cookalong")


def create_app(settings: Settings | None = None, llm: LLM | None = None) -> FastAPI:
    settings = settings or get_settings()
    app = FastAPI(title="CookAlong backend", version="1.0")
    app.state.settings = settings
    app.state.store = Store(settings.log_db_path)
    app.state.llm = llm
    app.state.llm_error = None
    if llm is None:
        try:
            app.state.llm = build_llm(settings)
        except LLMNotConfigured as e:
            # Start anyway so /health and /log work; model calls return 503.
            app.state.llm_error = str(e)
            log.warning("model not configured: %s", e)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=[o.strip() for o in settings.cors_origins.split(",")],
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type", "X-API-Key"],
    )
    _add_error_handlers(app)
    _add_routes(app)
    return app


def _error(status: int, message: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"error": message})


def _add_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(RequestValidationError)
    async def invalid(_: Request, exc: RequestValidationError):
        first = exc.errors()[0]
        field = ".".join(str(p) for p in first["loc"] if p != "body")
        return _error(400, f"invalid request: {field} {first['msg']}".strip())

    @app.exception_handler(HTTPException)
    async def http_error(_: Request, exc: HTTPException):
        return _error(exc.status_code, str(exc.detail))

    @app.exception_handler(BadImage)
    async def bad_image(_: Request, exc: BadImage):
        return _error(400, str(exc))

    @app.exception_handler(LLMNotConfigured)
    async def not_configured(_: Request, exc: LLMNotConfigured):
        return _error(503, f"assistant not configured: {exc}")

    @app.exception_handler(LLMTimeout)
    async def timed_out(_: Request, exc: LLMTimeout):
        log.warning("model timeout: %s", exc)
        return _error(504, "the assistant took too long to answer")

    @app.exception_handler(LLMError)
    async def llm_failed(_: Request, exc: LLMError):
        log.error("model error: %s", exc)
        return _error(502, "the assistant is unavailable right now")

    @app.exception_handler(Exception)
    async def unexpected(_: Request, exc: Exception):
        log.exception("unexpected error")
        return _error(500, "something went wrong on the server")


def _add_routes(app: FastAPI) -> None:
    def settings() -> Settings:
        return app.state.settings

    def require_key(x_api_key: str = Header(default="")) -> None:
        expected = app.state.settings.app_api_key
        if expected and not secrets.compare_digest(x_api_key, expected):
            raise HTTPException(401, "missing or wrong X-API-Key")

    def model() -> LLM:
        if app.state.llm is None:
            raise LLMNotConfigured(app.state.llm_error or "no model")
        return app.state.llm

    async def call_model(endpoint: str, session_id: str, llm: LLM, **kwargs) -> str:
        start = time.perf_counter()
        outcome = "ok"
        try:
            return await llm.complete(**kwargs)
        except LLMTimeout:
            outcome = "timeout"
            raise
        except LLMError:
            outcome = "error"
            raise
        finally:
            ms = round((time.perf_counter() - start) * 1000)
            app.state.store.add_llm_call(session_id, endpoint, llm.name, llm.model, ms, outcome)

    @app.get("/health")
    async def health():
        llm = app.state.llm
        return {
            "ok": True,
            "provider": llm.name if llm else app.state.settings.llm_provider,
            "model": llm.model if llm else None,
            "configured": llm is not None,
            "problem": app.state.llm_error,
        }

    # Fields left out of the response are omitted, so older apps still see
    # exactly {"reply": "..."}.
    @app.post(
        "/ask",
        response_model=AskResponse,
        response_model_exclude_none=True,
        dependencies=[Depends(require_key)],
    )
    async def ask(req: AskRequest, llm: LLM = Depends(model), s: Settings = Depends(settings)):
        opening = req.phase == "opening"
        raw = await call_model(
            "opening" if opening else "ask",
            req.session_id,
            llm,
            system=prompts.OPENING_SYSTEM if opening else prompts.ASK_SYSTEM,
            text=prompts.opening_context(req) if opening else prompts.ask_context(req),
            json_output=True,
            # Room for rewritten steps (adapt_steps) in the opening.
            max_tokens=600 if opening else 200,
            timeout=s.ask_timeout_s,
        )
        reply, offer, action = safety.parse_ask(raw, req)
        if not reply:
            raise LLMError("empty reply")
        return AskResponse(reply=reply, offer=offer, action=action)

    @app.post(
        "/check-step", response_model=CheckStepResponse, dependencies=[Depends(require_key)]
    )
    async def check_step(
        req: CheckStepRequest, llm: LLM = Depends(model), s: Settings = Depends(settings)
    ):
        jpeg = await run_in_threadpool(prepare_jpeg, req.image, s.max_image_side)
        raw = await call_model(
            "check-step",
            req.session_id,
            llm,
            system=prompts.CHECK_SYSTEM,
            text=prompts.check_context(req),
            image_jpeg=jpeg,
            json_output=True,
            max_tokens=200,
            timeout=s.check_timeout_s,
        )
        status, say = safety.parse_check(raw)
        return CheckStepResponse(status=status, say=say)

    @app.post("/log", response_model=LogResponse, dependencies=[Depends(require_key)])
    async def add_log(req: LogRequest):
        await run_in_threadpool(
            app.state.store.add_event, req.session_id, req.type, req.time, req.data
        )
        return LogResponse()

    @app.get("/export/events.csv", response_class=PlainTextResponse)
    async def export_events(x_admin_key: str = Header(default="")):
        expected = app.state.settings.admin_key
        if not expected:
            raise HTTPException(404, "export is turned off; set ADMIN_KEY to enable it")
        if not secrets.compare_digest(x_admin_key, expected):
            raise HTTPException(401, "missing or wrong X-Admin-Key")
        csv_text = await run_in_threadpool(app.state.store.events_csv)
        return PlainTextResponse(
            csv_text,
            media_type="text/csv",
            headers={"Content-Disposition": 'attachment; filename="events.csv"'},
        )


app = create_app()
