"""HTTP boundary tests against the production Traefik configuration."""

import http.client
import json
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.cookiejar import CookieJar
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import Request

import yaml


class Backend(BaseHTTPRequestHandler):
    def handle_request(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"backend reached")

    do_GET = do_HEAD = do_POST = do_PUT = do_DELETE = do_OPTIONS = handle_request

    def log_message(self, *_args):
        pass


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Routing(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.directory.cleanup)
        directory = Path(cls.directory.name)
        cls.backend = ThreadingHTTPServer(("127.0.0.1", 0), Backend)
        threading.Thread(target=cls.backend.serve_forever, daemon=True).start()
        cls.addClassCleanup(cls.backend.server_close)
        cls.addClassCleanup(cls.backend.shutdown)
        cls.ports = {name: free_port() for name in ["web", "websecure", "netbird"]}
        cls.start_nginx(directory)

        static = yaml.safe_load(Path(sys.argv[1]).read_text())
        dynamic = yaml.safe_load(Path(sys.argv[2]).read_text())
        for path in sys.argv[6:]:
            extra = yaml.safe_load(Path(path).read_text())["http"]
            for kind, values in extra.items():
                dynamic["http"].setdefault(kind, {}).update(values)
        for name, port in cls.ports.items():
            static["entryPoints"][name]["address"] = f"127.0.0.1:{port}"
        del static["certificatesResolvers"]
        static["providers"] = {"file": {"filename": str(directory / "dynamic.yml")}}
        for router in dynamic["http"]["routers"].values():
            router["tls"] = {}
        for service in dynamic["http"]["services"].values():
            service["loadBalancer"]["servers"] = [
                {"url": f"http://127.0.0.1:{cls.backend.server_port}"}
            ]
        dynamic["http"]["services"]["invoiceninja"]["loadBalancer"]["servers"] = [
            {"url": f"http://127.0.0.1:{cls.nginx_port}"}
        ]
        (directory / "static.yml").write_text(json.dumps(static))
        (directory / "dynamic.yml").write_text(json.dumps(dynamic))
        log = (directory / "traefik.log").open("w+")
        cls.addClassCleanup(log.close)
        cls.traefik = subprocess.Popen(
            ["traefik", "--configFile", str(directory / "static.yml")],
            stdout=log,
            stderr=log,
        )
        cls.addClassCleanup(cls.stop_traefik)
        for _ in range(100):
            try:
                connection = http.client.HTTPSConnection(
                    "127.0.0.1",
                    cls.ports["websecure"],
                    timeout=1,
                    context=ssl._create_unverified_context(),
                )
                connection.request(
                    "POST",
                    "/api/v1/sns_webhook",
                    headers={"Host": "billing-sns.denys.me"},
                )
                ready = connection.getresponse().status == 200
                connection.close()
                if ready:
                    return
            except OSError:
                if cls.traefik.poll() is not None:
                    break
            time.sleep(0.1)
        log.seek(0)
        raise AssertionError(log.read())

    @classmethod
    def start_nginx(cls, directory):
        cls.nginx_port, php_port = free_port(), free_port()
        root = directory / "public"
        root.mkdir()
        (root / "index.php").write_text(Path(sys.argv[5]).read_text())
        for asset in [
            "build/app.css",
            "build/assets/app.css",
            "vendor/cookieconsent@3/cookieconsent.min.js",
            "storage/company/logo.png",
        ]:
            path = root / asset
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("portal asset")
        (root / "build" / "unexpected.php").write_text('<?php echo "executed PHP";')
        config = Path(sys.argv[3]).read_text()
        config = config.replace(
            "listen 80 default_server;", f"listen 127.0.0.1:{cls.nginx_port};"
        )
        config = config.replace("/var/www/html/public", str(root))
        config = config.replace("invoiceninja-app:9000", f"127.0.0.1:{php_port}")
        config = config.replace("include fastcgi_params;", f"include {sys.argv[4]};")
        (directory / "nginx.conf").write_text(
            f"daemon off; pid {directory}/nginx.pid; error_log stderr; events {{}} "
            f"http {{ access_log off; client_body_temp_path {directory}/body; "
            f"fastcgi_temp_path {directory}/fastcgi; {config} }}"
        )
        for command in [
            [
                "php-cgi",
                "-d",
                f"session.save_path={directory}",
                "-b",
                f"127.0.0.1:{php_port}",
            ],
            [
                "nginx",
                "-e",
                "stderr",
                "-c",
                str(directory / "nginx.conf"),
                "-p",
                str(directory),
            ],
        ]:
            process = subprocess.Popen(command, stdout=subprocess.DEVNULL)
            cls.addClassCleanup(cls.stop_process, process)
        for port in [php_port, cls.nginx_port]:
            for _ in range(100):
                try:
                    with socket.create_connection(("127.0.0.1", port), 0.1):
                        break
                except OSError:
                    time.sleep(0.1)
            else:
                raise AssertionError(f"server not listening: {port}")

    @staticmethod
    def stop_process(process):
        process.terminate()
        process.wait(timeout=10)

    @classmethod
    def stop_traefik(cls):
        cls.traefik.terminate()
        cls.traefik.wait(timeout=10)

    def request(
        self, host, path, method="GET", entrypoint="websecure", headers=None, body=None
    ):
        connection = http.client.HTTPSConnection(
            "127.0.0.1",
            self.ports[entrypoint],
            context=ssl._create_unverified_context(),
        )
        try:
            connection.request(
                method, path, body=body, headers={"Host": host, **(headers or {})}
            )
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def browser_request(self, jar, url, method="GET"):
        """Keep real cookie origins while connecting only to the test listeners."""
        parts = urlsplit(url)
        entrypoint = {
            "billing.denys.me": "websecure",
            "billing.vpn.denys.me": "netbird",
        }[parts.hostname]
        request = Request(url, method=method)
        jar.add_cookie_header(request)
        connection = http.client.HTTPSConnection(
            "127.0.0.1",
            self.ports[entrypoint],
            context=ssl._create_unverified_context(),
        )
        try:
            path = parts.path + (f"?{parts.query}" if parts.query else "")
            connection.request(
                method,
                path,
                headers={"Host": parts.hostname, **dict(request.header_items())},
            )
            response = connection.getresponse()
            jar.extract_cookies(response, request)
            return response.status, response.read(), response.headers
        finally:
            connection.close()

    def test_mailer_oauth_state_round_trip_uses_public_host_only_cookie(self):
        # PHP models Socialite's session state, not provider/token verification.
        # Neither the private session nor a bearer token is needed to initiate.
        for provider in ["google", "microsoft"]:
            with self.subTest(provider=provider):
                jar = CookieJar()
                self.browser_request(jar, "https://billing.vpn.denys.me/login")
                private_cookie = next(iter(jar))
                initiation = f"/auth/{provider}?react=true&marker=a%2Bb"
                public_url = "https://billing.denys.me" + initiation
                status, _, headers = self.browser_request(
                    jar, "https://billing.vpn.denys.me" + initiation
                )
                self.assertEqual(status, 302)
                self.assertEqual(headers["Location"], public_url)
                self.assertIsNone(
                    headers["Set-Cookie"],
                    "redirect must precede Laravel session creation",
                )
                self.assertEqual(len(jar), 1)

                status, _, headers = self.browser_request(jar, public_url)
                self.assertEqual(status, 302)
                provider_url = urlsplit(headers["Location"])
                self.assertEqual(provider_url.hostname, "provider.invalid")
                params = parse_qs(provider_url.query)
                self.assertEqual(
                    params["redirect_uri"],
                    [f"https://billing.denys.me/auth/{provider}"],
                )
                self.assertTrue(params["state"][0])
                cookies = {cookie.domain: cookie for cookie in jar}
                self.assertEqual(
                    set(cookies), {"billing.denys.me", "billing.vpn.denys.me"}
                )
                self.assertNotEqual(
                    cookies["billing.denys.me"].value, private_cookie.value
                )
                self.assertTrue(
                    all(not cookie.domain_specified and cookie.secure for cookie in jar)
                )

                callback = (
                    params["redirect_uri"][0]
                    + "?"
                    + urlencode(
                        {
                            "code": "modeled-provider-code",
                            "state": params["state"][0],
                        }
                    )
                )
                status, _, _ = self.browser_request(CookieJar(), callback)
                self.assertEqual(
                    status, 400, "a callback without its session must fail"
                )
                status, _, headers = self.browser_request(jar, callback)
                self.assertEqual(status, 302)
                self.assertEqual(
                    headers["Location"],
                    "https://billing.vpn.denys.me/#/settings/user_details/connect",
                )
                self.assertEqual(
                    self.browser_request(jar, callback)[0],
                    400,
                    "state must be consumed",
                )

                _, _, headers = self.browser_request(jar, public_url)
                params = parse_qs(urlsplit(headers["Location"]).query)
                wrong_state = (
                    params["redirect_uri"][0]
                    + "?code=modeled-provider-code&state=wrong"
                )
                self.assertEqual(self.browser_request(jar, wrong_state)[0], 400)
                # HEAD follows the same exact redirect, without widening the route.
                self.assertEqual(
                    self.browser_request(
                        jar, "https://billing.vpn.denys.me" + initiation, "HEAD"
                    )[2]["Location"],
                    public_url,
                )
                self.assertEqual(
                    self.request("billing.vpn.denys.me", initiation)[0], 404
                )

    def test_larapaper_devices_public_administration_private(self):
        for method, path in [
            ("GET", "/api/setup"),
            ("GET", "/api/display"),
            ("GET", "/api/current_screen"),
            ("POST", "/api/log"),
            ("POST", "/api/screens"),
            ("GET", "/storage/images/generated/screen.bmp"),
            ("GET", "/storage/firmwares/firmware.bin"),
            ("POST", "/api/custom_plugins/550e8400-e29b-41d4-a716-446655440000"),
            ("POST", "/api/plugins/550e8400-e29b-41d4-a716-446655440000/webhook"),
        ]:
            with self.subTest(method=method, path=path):
                self.assertEqual(self.request("trmnl.denys.me", path, method)[0], 200)
        for path in [
            "/",
            "/login",
            "/dashboard",
            "/api/devices",
            "/api/display/status",
            "/api/display/update",
        ]:
            with self.subTest(path=path):
                self.assertEqual(self.request("trmnl.denys.me", path)[0], 404)
                self.assertEqual(self.request("trmnl.vpn.denys.me", path)[0], 404)
                self.assertEqual(
                    self.request("trmnl.vpn.denys.me", path, entrypoint="netbird")[0],
                    200,
                )
        self.assertEqual(self.request("trmnl.denys.me", "/api/display", "POST")[0], 404)

    def test_invoice_customers_and_callbacks_public_admin_private(self):
        for method, path in [
            ("GET", "/client"),
            ("GET", "/client/invoice/invitation-key"),
            ("GET", "/client/pay/invitation-key"),
            ("PUT", "/client/profile/contact/edit"),
            ("POST", "/client/payment_methods/token"),
            ("POST", "/livewire/update"),
            ("POST", "/livewire/upload-file?signature=test"),
            ("GET", "/livewire/preview-file/file.png?signature=test"),
            ("GET", "/build/assets/app.css"),
            ("GET", "/vendor/cookieconsent@3/cookieconsent.min.js"),
            ("GET", "/storage/company/logo.png"),
            ("GET", "/documents/document-hash"),
            ("POST", "/api/v1/contact/login"),
            ("GET", "/api/v1/contact/invoices"),
            ("GET", "/api/v1/shop/products"),
            ("POST", "/api/v1/shop/invoices"),
            ("POST", "/payment_webhook/company/gateway"),
            ("GET", "/payment_notification_webhook/company/gateway/client"),
            ("POST", "/payments/process/response"),
            ("POST", "/api/v1/ppcp/webhook"),
            ("GET", "/checkout/3ds_redirect/company/gateway/hash"),
            ("GET", "/.well-known/apple-developer-merchantid-domain-association"),
            ("GET", "/stripe/completed?code=test"),
            ("GET", "/square/callback?code=test"),
        ]:
            with self.subTest(method=method, path=path):
                self.assertEqual(self.request("billing.denys.me", path, method)[0], 200)
        for provider in ["google", "microsoft"]:
            self.assertEqual(
                self.request("billing.denys.me", f"/auth/{provider}", "POST")[0], 404
            )
        for path in [
            "/",
            "/login",
            "/setup",
            "/update",
            "/api/v1/login",
            "/api/v1/invoices",
            "/api/v1/users",
            "/api/v1/tokens",
            "/token_hash_router",
            "/build-admin/app.js",
            "/index.php",
            "/clientele",
            "/auth/apple",
            "/auth/google/extra",
        ]:
            with self.subTest(path=path):
                for method in ["GET", "POST"]:
                    self.assertEqual(
                        self.request("billing.denys.me", path, method)[0], 404
                    )
                    self.assertEqual(
                        self.request("billing.vpn.denys.me", path, method)[0], 404
                    )
                expected_private = 404 if path == "/index.php" else 200
                self.assertEqual(
                    self.request("billing.vpn.denys.me", path, entrypoint="netbird")[0],
                    expected_private,
                )

    def test_vendor_portal_reaches_laravel_but_missing_assets_do_not(self):
        # Exact v5.13.29 routes/vendor.php contracts, plus the profile Blade
        # form's POST _method=PUT transport. Laravel keeps vendor auth/CSRF.
        routes = [
            ("GET", "/vendors"),
            ("GET", "/vendor/key_login/contact-key"),
            ("GET", "/vendor/purchase_order/invitation-key"),
            ("GET", "/vendor/purchase_order/invitation-key/download"),
            ("GET", "/vendor/purchase_order/invitation-key/download_e_purchase_order"),
            ("GET", "/vendor/dashboard"),
            ("GET", "/vendor/purchase_orders"),
            ("GET", "/vendor/purchase_orders/order-id"),
            ("GET", "/vendor/showBlob/document-hash"),
            ("GET", "/vendor/profile/contact-id/edit"),
            ("PUT", "/vendor/profile/contact-id/edit"),
            ("POST", "/vendor/profile/contact-id/edit"),
            ("GET", "/vendor/logout"),
            ("GET", "/vendor/documents"),
            ("GET", "/vendor/documents/document-id"),
            ("GET", "/vendor/documents/document-id/download"),
            ("GET", "/vendor/documents/document-id/download_pdf"),
            ("POST", "/vendor/documents/download_multiple"),
            ("POST", "/vendor/purchase_orders/bulk"),
            ("POST", "/vendor/purchase_order/upload/order-id"),
        ]
        for host, entrypoint in [
            ("billing.denys.me", "websecure"),
            ("billing.vpn.denys.me", "netbird"),
        ]:
            for method, path in routes:
                methods = ["GET", "HEAD"] if method == "GET" else [method]
                for verb in methods:
                    with self.subTest(host=host, method=verb, path=path):
                        status, body = self.request(
                            host,
                            path + "?portal=test%2Bquery",
                            verb,
                            entrypoint,
                            headers={
                                "Content-Type": "application/x-www-form-urlencoded"
                            },
                            body="_method=PUT"
                            if verb == "POST" and "/profile/" in path
                            else None,
                        )
                        self.assertEqual(status, 200)
                        if verb == "HEAD":
                            self.assertEqual(body, b"")
                        else:
                            received = json.loads(body)
                            self.assertEqual(
                                received["uri"], path + "?portal=test%2Bquery"
                            )
                            self.assertEqual(received["method"], verb)
                            if verb == "POST" and "/profile/" in path:
                                self.assertEqual(received["form"], {"_method": "PUT"})
            for path in [
                "/vendor/missing.js",
                "/vendor/cookieconsent@3/missing.js",
                "/vendor/admin",
                "/vendor/purchase_order/key/extra",
                "/vendor/profile/key/edit/extra",
                "/vendor/documents/key/extra",
            ]:
                with self.subTest(host=host, path=path):
                    status, body = self.request(host, path, entrypoint=entrypoint)
                    self.assertEqual(status, 404)
                    self.assertNotIn(b"front controller", body)
            self.assertEqual(
                self.request(
                    host,
                    "/vendor/cookieconsent@3/cookieconsent.min.js",
                    entrypoint=entrypoint,
                ),
                (200, b"portal asset"),
            )
        for method, path in [
            ("POST", "/vendors"),
            ("POST", "/vendor/key_login/key"),
            ("POST", "/vendor/purchase_order/key/download"),
            ("POST", "/vendor/documents"),
            ("PUT", "/vendor/documents/key"),
            ("DELETE", "/vendor/profile/key/edit"),
            ("POST", "/vendor/cookieconsent@3/cookieconsent.min.js"),
            ("GET", "/api/v1/vendors"),
            ("POST", "/api/v1/purchase_orders"),
        ]:
            with self.subTest(method=method, path=path):
                self.assertEqual(self.request("billing.denys.me", path, method)[0], 404)
        self.assertEqual(
            self.request("billing.vpn.denys.me", "/vendor/dashboard")[0], 404
        )

    def test_public_paths_cannot_be_reinterpreted_as_administration(self):
        for host, prefix, admin in [
            ("billing.denys.me", "/client", "/api/v1/users"),
            ("billing.denys.me", "/vendor", "/api/v1/vendors"),
            ("trmnl.denys.me", "/storage/images", "/dashboard"),
        ]:
            for path in [
                prefix + "/" + "../" * prefix.count("/") + admin[1:],
                prefix + "/" + "%2e%2e/" * prefix.count("/") + admin[1:],
                prefix + "/" + "%252e%252e%252f" * prefix.count("/") + admin[1:],
                prefix + "%2f..%2f" + admin[1:],
                prefix + "/%5c..%5c" + admin[1:],
                prefix + "/x%3f/" + admin[1:],
                prefix + "/x%23/" + admin[1:],
                prefix + "/x%00/" + admin[1:],
                prefix + "/x%3b/" + admin[1:],
            ]:
                with self.subTest(host=host, path=path):
                    status, body = self.request(host, path)
                    self.assertIn(status, [400, 404])
                    self.assertNotIn(b"backend reached", body)
                    self.assertNotIn(b"front controller", body)
            status, _ = self.request(
                host,
                admin,
                headers={
                    "X-Forwarded-Host": host.replace(".denys.me", ".vpn.denys.me"),
                    "X-Original-URL": prefix,
                    "X-Rewrite-URL": prefix,
                },
            )
            self.assertEqual(status, 404)

    def test_sns_remains_dedicated_exact_post(self):
        for host in [
            "billing.denys.me",
            "billing-sns.denys.me",
            "billing.vpn.denys.me",
        ]:
            for method in ["GET", "POST", "PUT"]:
                for path in [
                    "/api/v1/sns_webhook",
                    "/api/v1/sns_webhook/",
                    "/api/v1/sns_webhook/extra",
                    "/api/v1/sns_webhook-other",
                ]:
                    with self.subTest(host=host, method=method, path=path):
                        expected = (
                            200
                            if host == "billing-sns.denys.me"
                            and method == "POST"
                            and path == "/api/v1/sns_webhook"
                            else 404
                        )
                        self.assertEqual(self.request(host, path, method)[0], expected)

    def test_invoice_static_files_never_fall_through_to_php(self):
        for path, expected_status, expected_body in [
            ("/client/invoice/key", 200, b"front controller"),
            ("/build/app.css", 200, b"portal asset"),
            ("/build/missing.css", 404, None),
            ("/build/unexpected.php", 404, None),
            ("/storage/missing.png", 404, None),
        ]:
            with self.subTest(path=path):
                connection = http.client.HTTPConnection("127.0.0.1", self.nginx_port)
                connection.request("GET", path, headers={"Host": "billing.denys.me"})
                response = connection.getresponse()
                body = response.read()
                connection.close()
                self.assertEqual(response.status, expected_status)
                if expected_body is not None:
                    self.assertEqual(body, expected_body)
                else:
                    self.assertNotIn(b"front controller", body)
                    self.assertNotIn(b"executed PHP", body)

    def test_existing_cpa_clients_and_paseo_remain_public(self):
        for method, path in [
            ("GET", "/v1/models"),
            ("POST", "/v1/chat/completions"),
            ("GET", "/v1/responses"),
            ("POST", "/v1beta/models/gemini:generateContent"),
            ("POST", "/openai/v1/videos"),
            ("POST", "/backend-api/codex/responses"),
            ("GET", "/v0/resource/plugins/pi-bridge/capabilities"),
            ("GET", "/v0/resource/plugins/pi-bridge/usage"),
            ("GET", "/v0/resource/plugins/pi-bridge/well-known"),
        ]:
            with self.subTest(method=method, path=path):
                self.assertEqual(self.request("cpa.pvlv.ca", path, method)[0], 200)
        for host in ["cpa.pvlv.ca", "cpa.vpn.denys.me"]:
            for path in [
                "/",
                "/v0/management/config",
                "/management.html",
                "/usage-service/info",
                "/v0/resource/plugins/pi-bridge/panel",
                "/v0/resource/plugins/pi-bridge/dev/usage",
                "/codex/callback",
            ]:
                with self.subTest(host=host, path=path):
                    self.assertEqual(self.request(host, path)[0], 404)
        self.assertEqual(
            self.request("cpa.vpn.denys.me", "/", entrypoint="netbird")[0], 200
        )
        self.assertEqual(self.request("paseo.denys.me", "/")[0], 200)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]], verbosity=2)
