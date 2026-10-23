"""Decode the app's base64 photo and shrink it before it goes to a model."""

import base64
import binascii
import io

from PIL import Image, UnidentifiedImageError


class BadImage(ValueError):
    pass


def prepare_jpeg(b64: str, max_side: int) -> bytes:
    """Return JPEG bytes no larger than max_side on the long edge."""
    # Accept a data: URL too, although the contract says there is none.
    if b64.startswith("data:"):
        b64 = b64.split(",", 1)[-1]
    try:
        raw = base64.b64decode(b64, validate=True)
    except (binascii.Error, ValueError) as e:
        raise BadImage("image is not valid base64") from e

    try:
        img = Image.open(io.BytesIO(raw))
        img.load()
    except (UnidentifiedImageError, OSError) as e:
        raise BadImage("image is not a readable photo") from e

    img = img.convert("RGB")
    img.thumbnail((max_side, max_side))
    out = io.BytesIO()
    img.save(out, format="JPEG", quality=85)
    return out.getvalue()
