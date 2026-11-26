"""Apply the SQLite schema migrations without third-party dependencies."""

import os
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DEFAULT_DATABASE = ROOT / "data" / "calm.sqlite3"


def database_path() -> Path:
    return Path(os.environ.get("DATABASE_PATH", DEFAULT_DATABASE)).expanduser()


def connect(path: Path | None = None) -> sqlite3.Connection:
    location = path or database_path()
    location.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(location, timeout=10)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA busy_timeout = 10000")
    return connection


def migrate(path: Path | None = None) -> None:
    db = connect(path)
    try:
        current = db.execute("PRAGMA user_version").fetchone()[0]
        migrations = sorted((ROOT / "migrations").glob("[0-9][0-9][0-9][0-9]_*.sql"))
        if current > len(migrations):
            raise RuntimeError("Database schema is newer than this application")
        for version, script in enumerate(migrations, start=1):
            if version > current:
                db.executescript(script.read_text(encoding="utf-8"))
                applied = db.execute("PRAGMA user_version").fetchone()[0]
                if applied != version:
                    raise RuntimeError(f"Migration {script.name} did not set schema version {version}")
    finally:
        db.close()


if __name__ == "__main__":
    target = database_path()
    migrate(target)
    print(f"Database ready: {target}")
