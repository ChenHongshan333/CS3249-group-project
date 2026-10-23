"""Request and response bodies, matching docs/api.md."""

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator
from pydantic.alias_generators import to_camel


class _Body(BaseModel):
    # The app sends camelCase (sessionId); Python code uses snake_case.
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class Turn(_Body):
    from_: Literal["assistant", "user"] = Field(alias="from")
    text: str = Field(max_length=2000)


ActionType = Literal["start_timer", "next_step", "repeat_step", "start_cooking", "tick_ingredient"]

# Which actions make sense in each phase. Anything else from the model is dropped.
PHASE_ACTIONS: dict[str, set[str]] = {
    "opening": {"start_cooking", "tick_ingredient"},
    "cooking": {"start_timer", "next_step", "repeat_step"},
}


class Action(_Body):
    """Something the app does, or something CookAlong offers to do."""

    type: ActionType
    seconds: int | None = Field(default=None, ge=1, le=3600)
    label: str | None = Field(default=None, max_length=60)
    name: str | None = Field(default=None, max_length=100)
    names: list[str] | None = Field(default=None, max_length=40)


class Ingredient(_Body):
    name: str = Field(max_length=100)
    ready: bool = False


class AskRequest(_Body):
    session_id: str = Field(max_length=100)
    recipe_id: str = Field(max_length=100)
    recipe_name: str = Field(default="", max_length=200)
    phase: Literal["opening", "cooking"] = "cooking"
    # Required while cooking; the opening has no current step yet.
    step: int = Field(default=0, ge=0)
    step_text: str = Field(default="", max_length=2000)
    next_step_title: str = Field(default="", max_length=200)
    question: str = Field(min_length=1, max_length=1000)
    accepted_swaps: list[str] = Field(default_factory=list, max_length=20)
    ingredients: list[Ingredient] = Field(default_factory=list, max_length=40)
    history: list[Turn] = Field(default_factory=list, max_length=50)
    pending_offer: Action | None = None

    @model_validator(mode="after")
    def _cooking_needs_step_text(self):
        if self.phase == "cooking" and not self.step_text.strip():
            raise ValueError("stepText is required while cooking")
        return self


class AskResponse(BaseModel):
    reply: str
    offer: Action | None = None
    action: Action | None = None


CheckStatus = Literal["done", "not_yet", "unsure"]

# About 10 MB of base64. The image is shrunk before it goes to the model.
MAX_IMAGE_B64 = 14_000_000


class CheckStepRequest(_Body):
    session_id: str = Field(max_length=100)
    recipe_id: str = Field(max_length=100)
    step: int = Field(ge=0)
    step_text: str = Field(max_length=2000)
    done_looks_like: str = Field(default="", max_length=1000)
    image: str = Field(min_length=1, max_length=MAX_IMAGE_B64)
    source: Literal["glasses", "phone"] = "glasses"
    # Not in the original contract: the app also sends what the user asked,
    # e.g. "does this look chopped small enough?".
    question: str | None = Field(default=None, max_length=1000)


class CheckStepResponse(BaseModel):
    status: CheckStatus
    say: str


EventType = Literal[
    "session_start",
    "step_next",
    "step_repeat",
    "pause",
    "resume",
    "question",
    "check",
    "swap",
    "misheard",
    "opening_end",
    "session_end",
]


class LogRequest(_Body):
    session_id: str = Field(max_length=100)
    type: EventType
    time: str = Field(default="", max_length=64)
    data: dict[str, Any] = Field(default_factory=dict)


class LogResponse(BaseModel):
    ok: bool = True
