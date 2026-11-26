"""Small registration API backed by SQLite. Run `migrate.py` before serving."""

import hashlib
import hmac
import json
import os
import re
import secrets
import smtplib
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

from migrate import connect, database_path, migrate

EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
CODE_TTL = timedelta(minutes=10)
SESSION_TTL = timedelta(days=30)
RESEND_COOLDOWN = timedelta(minutes=1)
MAX_ATTEMPTS = 5


def now() -> datetime:
    return datetime.now(timezone.utc)


def timestamp(value: datetime) -> str:
    return value.isoformat(timespec="seconds")


def password_requirements(value: str) -> bool:
    return (
        8 <= len(value) <= 128
        and any(c.isupper() for c in value)
        and any(c.islower() for c in value)
        and any(c.isdigit() for c in value)
        and any(not c.isalnum() and not c.isspace() for c in value)
    )


def hash_password(value: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(value.encode(), salt=salt, n=16384, r=8, p=1)
    return f"scrypt$16384$8$1${salt.hex()}${digest.hex()}"


def check_password(value: str, encoded: str) -> bool:
    try:
        algorithm, n, r, p, salt, expected = encoded.split("$")
        if algorithm != "scrypt":
            return False
        digest = hashlib.scrypt(value.encode(), salt=bytes.fromhex(salt), n=int(n), r=int(r), p=int(p))
        return hmac.compare_digest(digest, bytes.fromhex(expected))
    except (ValueError, TypeError):
        return False


def code_hash(secret: str, user_id: str, code: str) -> str:
    return hmac.new(secret.encode(), f"{user_id}:{code}".encode(), hashlib.sha256).hexdigest()


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def public_user(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "first_name": row["first_name"],
        "last_name": row["last_name"],
        "email": row["email"],
        "email_verified": row["email_verified_at"] is not None,
    }


class APIError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


class RegistrationAPI:
    def __init__(self, path: Path, secret: str, debug_codes: bool = False):
        self.path = path
        self.secret = secret
        self.debug_codes = debug_codes
        migrate(path)

    def db(self) -> sqlite3.Connection:
        return connect(self.path)

    @contextmanager
    def session(self):
        db = self.db()
        try:
            with db:
                yield db
        finally:
            db.close()

    @staticmethod
    def normalize_email(value: object) -> str:
        if not isinstance(value, str):
            raise APIError(400, "invalid_email", "Укажите корректную почту")
        email = value.strip().lower()
        if len(email) > 254 or not EMAIL_PATTERN.fullmatch(email):
            raise APIError(400, "invalid_email", "Укажите корректную почту")
        return email

    def deliver_code(self, email: str, code: str) -> None:
        if self.debug_codes:
            return
        host = os.environ.get("SMTP_HOST")
        sender = os.environ.get("SMTP_FROM")
        if not host or not sender:
            raise APIError(503, "mail_unavailable", "Отправка писем не настроена")
        message = EmailMessage()
        message["From"] = sender
        message["To"] = email
        message["Subject"] = "Код подтверждения Calm"
        message.set_content(f"Ваш код подтверждения: {code}\nКод действует 10 минут.")
        try:
            with smtplib.SMTP(host, int(os.environ.get("SMTP_PORT", "587")), timeout=10) as smtp:
                smtp.starttls()
                user = os.environ.get("SMTP_USER")
                if user:
                    smtp.login(user, os.environ.get("SMTP_PASSWORD", ""))
                smtp.send_message(message)
        except (OSError, smtplib.SMTPException) as error:
            raise APIError(503, "mail_unavailable", "Не удалось отправить письмо") from error

    def register(self, data: dict) -> dict:
        first_name = data.get("first_name")
        last_name = data.get("last_name")
        password = data.get("password")
        if not isinstance(first_name, str) or not 1 <= len(first_name.strip()) <= 100:
            raise APIError(400, "invalid_first_name", "Укажите имя")
        if last_name is not None and (not isinstance(last_name, str) or len(last_name.strip()) > 100):
            raise APIError(400, "invalid_last_name", "Проверьте фамилию")
        if not isinstance(password, str) or not password_requirements(password):
            raise APIError(400, "weak_password", "Пароль не соответствует требованиям безопасности")
        email = self.normalize_email(data.get("email"))
        code = f"{secrets.randbelow(10000):04d}"
        current = now()
        with self.session() as db:
            db.execute("BEGIN IMMEDIATE")
            existing = db.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
            if existing and existing["email_verified_at"]:
                raise APIError(409, "email_taken", "Почта уже зарегистрирована")
            if existing:
                user_id = existing["id"]
                previous = db.execute("SELECT sent_at FROM email_verifications WHERE user_id = ?", (user_id,)).fetchone()
                if previous and current - datetime.fromisoformat(previous["sent_at"]) < RESEND_COOLDOWN:
                    raise APIError(429, "try_later", "Повторите через минуту")
                db.execute(
                    "UPDATE users SET first_name=?, last_name=?, password_hash=?, updated_at=? WHERE id=?",
                    (first_name.strip(), (last_name or "").strip() or None, hash_password(password), timestamp(current), user_id),
                )
            else:
                user_id = secrets.token_hex(16)
                db.execute(
                    "INSERT INTO users(id, first_name, last_name, email, password_hash, created_at, updated_at) VALUES(?,?,?,?,?,?,?)",
                    (user_id, first_name.strip(), (last_name or "").strip() or None, email,
                     hash_password(password), timestamp(current), timestamp(current)),
                )
            db.execute(
                "INSERT INTO email_verifications(user_id, code_hash, expires_at, attempts, sent_at) VALUES(?,?,?,?,?) "
                "ON CONFLICT(user_id) DO UPDATE SET code_hash=excluded.code_hash, expires_at=excluded.expires_at, attempts=0, sent_at=excluded.sent_at",
                (user_id, code_hash(self.secret, user_id, code), timestamp(current + CODE_TTL), 0, timestamp(current)),
            )
            self.deliver_code(email, code)
        response = {"status": "verification_required", "email": email}
        if self.debug_codes:
            response["debug_code"] = code
        return response

    def resend(self, data: dict) -> dict:
        email = self.normalize_email(data.get("email"))
        current = now()
        with self.session() as db:
            db.execute("BEGIN IMMEDIATE")
            user = db.execute("SELECT * FROM users WHERE email=?", (email,)).fetchone()
            if not user or user["email_verified_at"]:
                return {"status": "verification_required"}
            previous = db.execute("SELECT sent_at FROM email_verifications WHERE user_id=?", (user["id"],)).fetchone()
            if previous and current - datetime.fromisoformat(previous["sent_at"]) < RESEND_COOLDOWN:
                raise APIError(429, "try_later", "Повторите через минуту")
            code = f"{secrets.randbelow(10000):04d}"
            db.execute(
                "INSERT INTO email_verifications(user_id, code_hash, expires_at, attempts, sent_at) VALUES(?,?,?,?,?) "
                "ON CONFLICT(user_id) DO UPDATE SET code_hash=excluded.code_hash, expires_at=excluded.expires_at, attempts=0, sent_at=excluded.sent_at",
                (user["id"], code_hash(self.secret, user["id"], code), timestamp(current + CODE_TTL), 0, timestamp(current)),
            )
            self.deliver_code(email, code)
        response = {"status": "verification_required"}
        if self.debug_codes:
            response["debug_code"] = code
        return response

    def new_session(self, db: sqlite3.Connection, user: sqlite3.Row) -> dict:
        token = secrets.token_urlsafe(32)
        current = now()
        db.execute(
            "INSERT INTO sessions(token_hash, user_id, created_at, expires_at) VALUES(?,?,?,?)",
            (token_hash(token), user["id"], timestamp(current), timestamp(current + SESSION_TTL)),
        )
        return {"token": token, "user": public_user(user)}

    def verify(self, data: dict) -> dict:
        email = self.normalize_email(data.get("email"))
        code = data.get("code")
        if not isinstance(code, str) or not re.fullmatch(r"[0-9]{4}", code):
            raise APIError(400, "invalid_code", "Введите четырёхзначный код")
        with self.session() as db:
            db.execute("BEGIN IMMEDIATE")
            user = db.execute("SELECT * FROM users WHERE email=?", (email,)).fetchone()
            if not user or user["email_verified_at"]:
                raise APIError(400, "invalid_code", "Неверный код")
            challenge = db.execute("SELECT * FROM email_verifications WHERE user_id=?", (user["id"],)).fetchone()
            if not challenge or now() >= datetime.fromisoformat(challenge["expires_at"]):
                raise APIError(400, "expired_code", "Срок действия кода истёк")
            if challenge["attempts"] >= MAX_ATTEMPTS:
                raise APIError(429, "too_many_attempts", "Запросите новый код")
            if not hmac.compare_digest(challenge["code_hash"], code_hash(self.secret, user["id"], code)):
                db.execute("UPDATE email_verifications SET attempts=attempts+1 WHERE user_id=?", (user["id"],))
                db.commit()
                raise APIError(400, "invalid_code", "Неверный код")
            db.execute("UPDATE users SET email_verified_at=?, updated_at=? WHERE id=?", (timestamp(now()), timestamp(now()), user["id"]))
            db.execute("DELETE FROM email_verifications WHERE user_id=?", (user["id"],))
            verified = db.execute("SELECT * FROM users WHERE id=?", (user["id"],)).fetchone()
            return self.new_session(db, verified)

    def login(self, data: dict) -> dict:
        email = self.normalize_email(data.get("email"))
        password = data.get("password")
        if not isinstance(password, str):
            raise APIError(400, "invalid_password", "Укажите пароль")
        with self.session() as db:
            user = db.execute("SELECT * FROM users WHERE email=?", (email,)).fetchone()
            if not user or not check_password(password, user["password_hash"]):
                raise APIError(401, "invalid_credentials", "Неверная почта или пароль")
            if not user["email_verified_at"]:
                raise APIError(403, "email_not_verified", "Подтвердите почту")
            return self.new_session(db, user)

    def authenticate(self, authorization: str) -> tuple[sqlite3.Connection, sqlite3.Row, str]:
        if not authorization.startswith("Bearer "):
            raise APIError(401, "unauthorized", "Требуется авторизация")
        token = authorization.removeprefix("Bearer ")
        if len(token) < 30:
            raise APIError(401, "unauthorized", "Требуется авторизация")
        db = self.db()
        row = db.execute(
            "SELECT users.*, sessions.token_hash FROM sessions JOIN users ON users.id=sessions.user_id "
            "WHERE sessions.token_hash=? AND sessions.expires_at>?",
            (token_hash(token), timestamp(now())),
        ).fetchone()
        if not row:
            db.close()
            raise APIError(401, "unauthorized", "Требуется авторизация")
        return db, row, token_hash(token)


def handler_for(api: RegistrationAPI):
    class Handler(BaseHTTPRequestHandler):
        def respond(self, status: int, payload: dict | None = None) -> None:
            body = json.dumps(payload or {}, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body) if status != 204 else 0))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            if status != 204:
                self.wfile.write(body)

        def read_json(self) -> dict:
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError as error:
                raise APIError(400, "invalid_json", "Некорректный запрос") from error
            if length < 2 or length > 16384:
                raise APIError(400, "invalid_json", "Некорректный запрос")
            try:
                data = json.loads(self.rfile.read(length))
            except (ValueError, UnicodeDecodeError) as error:
                raise APIError(400, "invalid_json", "Некорректный запрос") from error
            if not isinstance(data, dict):
                raise APIError(400, "invalid_json", "Некорректный запрос")
            return data

        def route(self) -> None:
            path = urlsplit(self.path).path
            if self.command == "GET" and path == "/health":
                self.respond(200, {"status": "ok"})
            elif self.command == "POST" and path == "/v1/auth/register":
                self.respond(202, api.register(self.read_json()))
            elif self.command == "POST" and path == "/v1/auth/resend-code":
                self.respond(202, api.resend(self.read_json()))
            elif self.command == "POST" and path == "/v1/auth/verify-email":
                self.respond(200, api.verify(self.read_json()))
            elif self.command == "POST" and path == "/v1/auth/login":
                self.respond(200, api.login(self.read_json()))
            elif self.command == "GET" and path == "/v1/auth/me":
                db, user, _ = api.authenticate(self.headers.get("Authorization", ""))
                try:
                    self.respond(200, {"user": public_user(user)})
                finally:
                    db.close()
            elif self.command == "POST" and path == "/v1/auth/logout":
                db, _, digest = api.authenticate(self.headers.get("Authorization", ""))
                try:
                    with db:
                        db.execute("DELETE FROM sessions WHERE token_hash=?", (digest,))
                    self.respond(204)
                finally:
                    db.close()
            else:
                raise APIError(404, "not_found", "Маршрут не найден")

        def do_GET(self) -> None:
            self.handle_request()

        def do_POST(self) -> None:
            self.handle_request()

        def handle_request(self) -> None:
            try:
                self.route()
            except APIError as error:
                self.respond(error.status, {"error": error.code, "message": error.message})
            except sqlite3.Error:
                self.respond(500, {"error": "database_error", "message": "Ошибка базы данных"})

        def log_message(self, format: str, *args: object) -> None:
            if os.environ.get("APP_ENV") == "development":
                super().log_message(format, *args)

    return Handler


def main() -> None:
    secret = os.environ.get("APP_SECRET", "")
    if len(secret) < 32:
        raise SystemExit("APP_SECRET must be at least 32 characters")
    debug_codes = os.environ.get("APP_ENV") == "development" and os.environ.get("ALLOW_DEBUG_CODES") == "1"
    if not debug_codes and (not os.environ.get("SMTP_HOST") or not os.environ.get("SMTP_FROM")):
        raise SystemExit("Configure SMTP_HOST and SMTP_FROM, or enable local development debug codes")
    path = database_path()
    api = RegistrationAPI(path, secret, debug_codes)
    host = os.environ.get("HOST", "127.0.0.1")
    port = int(os.environ.get("PORT", "8000"))
    with ThreadingHTTPServer((host, port), handler_for(api)) as httpd:
        print(f"Registration API listening on {host}:{port}; database: {path}", flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
