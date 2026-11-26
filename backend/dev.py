"""Run the API locally with visible test verification codes and a persistent secret."""

import os
import secrets
from pathlib import Path

from server import main


def development_secret() -> str:
    location = Path(__file__).resolve().parent / "data" / "dev-secret"
    location.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(location, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        pass
    else:
        with os.fdopen(descriptor, "w") as output:
            output.write(secrets.token_urlsafe(32))
    return location.read_text(encoding="utf-8").strip()


if __name__ == "__main__":
    os.environ.setdefault("APP_SECRET", development_secret())
    os.environ["APP_ENV"] = "development"
    os.environ["ALLOW_DEBUG_CODES"] = "1"
    main()
