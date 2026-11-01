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
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

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
                connection.request("GET", "/v1/models", headers={"Host": "cpa.pvlv.ca"})
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
        (root / "build").mkdir()
        (root / "build" / "app.css").write_text("portal asset")
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

    def test_invoice_is_netbird_only(self):
        routes = [
            ("GET", "/"),
            ("GET", "/login"),
            ("GET", "/client/invoice/invitation-key"),
            ("GET", "/vendor/dashboard"),
            ("GET", "/auth/google"),
            ("POST", "/api/v1/login"),
            ("POST", "/api/v1/sns_webhook"),
            ("POST", "/payment_webhook/company/gateway"),
        ]
        for host in [
            "billing.denys.me",
            "billing-sns.denys.me",
            "billing.vpn.denys.me",
        ]:
            for method, path in routes:
                with self.subTest(host=host, method=method, path=path):
                    self.assertEqual(self.request(host, path, method)[0], 404)
        for method, path in routes:
            with self.subTest(entrypoint="netbird", method=method, path=path):
                self.assertEqual(
                    self.request("billing.vpn.denys.me", path, method, "netbird"),
                    (200, b"front controller"),
                )

    def test_invoice_nginx_never_executes_other_php(self):
        for path, expected_status, expected_body in [
            ("/client/invoice/key", 200, b"front controller"),
            ("/build/app.css", 200, b"portal asset"),
            ("/build/unexpected.php", 404, None),
            ("/index.php", 404, None),
        ]:
            with self.subTest(path=path):
                connection = http.client.HTTPConnection("127.0.0.1", self.nginx_port)
                connection.request(
                    "GET", path, headers={"Host": "billing.vpn.denys.me"}
                )
                response = connection.getresponse()
                body = response.read()
                connection.close()
                self.assertEqual(response.status, expected_status)
                if expected_body is not None:
                    self.assertEqual(body, expected_body)
                else:
                    self.assertNotIn(b"front controller", body)
                    self.assertNotIn(b"executed PHP", body)

    def test_public_paths_cannot_be_reinterpreted_as_administration(self):
        for host, prefix, admin in [
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

    def test_existing_cpa_clients_remain_public(self):
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

    def test_retired_paseo_relay_is_unavailable(self):
        self.assertEqual(self.request("paseo.denys.me", "/")[0], 404)

    def test_nix_cache_hides_metrics_and_forbids_edge_caching(self):
        self.assertEqual(self.request("cache.denys.me", "/metrics")[0], 404)
        connection = http.client.HTTPSConnection(
            "127.0.0.1",
            self.ports["websecure"],
            context=ssl._create_unverified_context(),
        )
        try:
            connection.request(
                "GET", "/nix-cache-info", headers={"Host": "cache.denys.me"}
            )
            response = connection.getresponse()
            self.assertEqual(response.status, 200)
            self.assertEqual(response.getheader("Cache-Control"), "no-store")
        finally:
            connection.close()


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]], verbosity=2)
