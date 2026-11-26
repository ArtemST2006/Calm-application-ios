import json
import sqlite3
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from server import APIError, RegistrationAPI, handler_for  # noqa: E402
from http.server import ThreadingHTTPServer


class RegistrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "test.sqlite3"
        self.api = RegistrationAPI(self.path, "test-secret-that-is-longer-than-32-characters", debug_codes=True)
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.api))
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.httpd.server_port}"

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=2)
        self.temp.cleanup()

    def request(self, method, path, body=None, token=None):
        data = json.dumps(body).encode() if body is not None else None
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        request = Request(self.base + path, data=data, headers=headers, method=method)
        try:
            with urlopen(request, timeout=5) as response:
                raw = response.read()
                return response.status, json.loads(raw) if raw else None
        except HTTPError as error:
            return error.code, json.loads(error.read())

    def registration_body(self):
        return {"first_name": "Иван", "last_name": "Иванов", "email": "Ivan@Example.com", "password": "GoodPass1!"}

    def test_registration_verify_login_and_logout(self):
        status, pending = self.request("POST", "/v1/auth/register", self.registration_body())
        self.assertEqual(status, 202)
        self.assertEqual(pending["email"], "ivan@example.com")
        self.assertRegex(pending["debug_code"], r"^[0-9]{4}$")

        status, response = self.request("POST", "/v1/auth/login", {"email": "ivan@example.com", "password": "GoodPass1!"})
        self.assertEqual((status, response["error"]), (403, "email_not_verified"))

        status, response = self.request("POST", "/v1/auth/verify-email", {"email": "ivan@example.com", "code": pending["debug_code"]})
        self.assertEqual(status, 200)
        self.assertTrue(response["user"]["email_verified"])
        token = response["token"]
        status, me = self.request("GET", "/v1/auth/me", token=token)
        self.assertEqual((status, me["user"]["first_name"]), (200, "Иван"))

        status, _ = self.request("POST", "/v1/auth/logout", token=token)
        self.assertEqual(status, 204)
        status, response = self.request("GET", "/v1/auth/me", token=token)
        self.assertEqual((status, response["error"]), (401, "unauthorized"))

        status, response = self.request("POST", "/v1/auth/login", {"email": "IVAN@example.com", "password": "GoodPass1!"})
        self.assertEqual(status, 200)
        self.assertNotEqual(response["token"], token)
        with sqlite3.connect(self.path) as db:
            password_hash = db.execute("SELECT password_hash FROM users WHERE email=?", ("ivan@example.com",)).fetchone()[0]
            self.assertNotIn("GoodPass1!", password_hash)

    def test_validation_duplicate_and_wrong_code_limit(self):
        body = self.registration_body()
        body["password"] = "weakpass"
        status, response = self.request("POST", "/v1/auth/register", body)
        self.assertEqual((status, response["error"]), (400, "weak_password"))

        body = self.registration_body()
        _, pending = self.request("POST", "/v1/auth/register", body)
        status, response = self.request("POST", "/v1/auth/register", body)
        self.assertEqual((status, response["error"]), (429, "try_later"))
        for _ in range(5):
            status, response = self.request("POST", "/v1/auth/verify-email", {"email": body["email"], "code": "9999" if pending["debug_code"] != "9999" else "8888"})
            self.assertEqual((status, response["error"]), (400, "invalid_code"))
        status, response = self.request("POST", "/v1/auth/verify-email", {"email": body["email"], "code": pending["debug_code"]})
        self.assertEqual((status, response["error"]), (429, "too_many_attempts"))

    def test_failed_mail_delivery_does_not_create_user(self):
        with patch.object(self.api, "deliver_code", side_effect=APIError(503, "mail_unavailable", "Почта недоступна")):
            status, response = self.request("POST", "/v1/auth/register", self.registration_body())
        self.assertEqual((status, response["error"]), (503, "mail_unavailable"))
        with sqlite3.connect(self.path) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM users").fetchone()[0], 0)


if __name__ == "__main__":
    unittest.main()
