# Registration API

Python 3.12 and SQLite are the only runtime requirements. The database is stored in `backend/data/calm.sqlite3` by default. For local development, run from the repository root:

```bash
python3 backend/dev.py
```

The development runner creates a persistent secret and automatically applies the database migration. It returns `debug_code` in the registration response so the iOS app can show a test code without email delivery. It listens only on `127.0.0.1` by default. For an iPhone on the same trusted local network, run `HOST=0.0.0.0 python3 backend/dev.py` and set the app's `API_BASE_URL` to the computer's LAN address. Never expose this debug runner to the public internet.

To send real verification emails, run:

```bash
python3 backend/migrate.py
APP_SECRET='replace-with-a-stable-random-secret-at-least-32-characters' \
  SMTP_HOST=smtp.example.com SMTP_FROM=calm@example.com \
  SMTP_USER=your-user SMTP_PASSWORD=your-password \
  python3 backend/server.py
```

Generate `APP_SECRET` once with `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`, store it outside the repository, and reuse it across restarts while verification codes are pending. Configure a real SMTP service before using the API with other people. `SMTP_PORT` defaults to `587` and the server uses STARTTLS. `DATABASE_PATH`, `HOST`, and `PORT` can be set in the environment. The default host is `127.0.0.1` and the default port is `8000`. For a phone on the same network, set `HOST=0.0.0.0` and configure the iOS app's `API_BASE_URL` to the computer's reachable address. Use HTTPS for traffic outside a trusted local network.

For local testing without SMTP, set `APP_ENV=development` and `ALLOW_DEBUG_CODES=1`. Only in that mode the registration and resend responses include `debug_code`. Never use this mode on a public server.

## API

All bodies are JSON. Successful registration creates an unverified user, sends a four-digit email code, and returns `202`. The code expires in 10 minutes and allows five attempts. Resend is limited to once per minute.

| Method | Path | JSON body | Result |
| --- | --- | --- | --- |
| `POST` | `/v1/auth/register` | `first_name`, optional `last_name`, `email`, `password` | `202`, verification pending |
| `POST` | `/v1/auth/verify-email` | `email`, `code` | `200`, user and session token |
| `POST` | `/v1/auth/resend-code` | `email` | `202`, new code |
| `POST` | `/v1/auth/login` | `email`, `password` | `200`, user and session token |
| `GET` | `/v1/auth/me` | `Authorization: Bearer <token>` | `200`, current user |
| `POST` | `/v1/auth/logout` | `Authorization: Bearer <token>` | `204` |
| `GET` | `/health` | — | `200` |

Passwords require at least eight characters, an uppercase letter, a lowercase letter, a digit, and a special character. Passwords are stored using salted `scrypt`; session tokens and verification codes are stored as hashes. The `users`, `email_verifications`, and `sessions` tables are created by `backend/migrations/0001_auth.sql`.

Run backend tests with `python3 -m unittest discover -s backend/tests -v`.
