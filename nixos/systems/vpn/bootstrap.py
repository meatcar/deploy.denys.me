import base64
import ipaddress
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request


STATE = Path("/var/lib/vpn")
ETC = Path("/etc/vpn")
NB_URL = "http://127.0.0.1:8081/api"
BAO_URL = "https://bao.vpn.denys.me/v1"


def write_private(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w") as target:
        os.chmod(temporary, 0o600)
        target.write(value)
    temporary.replace(path)


def command(*args, **kwargs):
    return subprocess.run(
        args, check=True, capture_output=True, text=True, **kwargs
    ).stdout


def request(base, path, method="GET", data=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        if base == NB_URL:
            headers["Authorization"] = "Token " + token
        else:
            headers["X-Vault-Token"] = token
    body = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(base + path, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as response:
        payload = response.read()
        return json.loads(payload) if payload else None


def wait_for(probe, message):
    for _ in range(90):
        try:
            result = probe()
            if result is not None:
                return result
        except (urllib.error.URLError, OSError):
            pass
        time.sleep(2)
    raise RuntimeError(message)


def host_role():
    role = (ETC / "role").read_text().strip()
    if role not in ("vpn", "bao"):
        raise ValueError("Unknown host role")
    return role


def prepare(data):
    role = host_role()
    names = ("backup",) if role == "vpn" else ("openbao", "backup", "acme")
    if set(data) != {*names, "repository"}:
        raise ValueError("Credentials do not match this host's role")
    for name in names:
        values = data[name]
        if any("\n" in str(value) or "\r" in str(value) for value in values.values()):
            raise ValueError("Environment credentials must be single-line values")
        write_private(
            ETC / (name + ".env"),
            "".join(f"{key}={json.dumps(value)}\n" for key, value in values.items()),
        )
    write_private(ETC / "restic-repository", data["repository"] + "\n")
    if not (ETC / "restic-password").exists():
        write_private(ETC / "restic-password", secrets.token_urlsafe(48) + "\n")
    if role == "bao":
        command("systemctl", "restart", "acme-bao.vpn.denys.me.service")
        return
    if not (STATE / "config.json").exists():

        def key():
            return base64.b64encode(secrets.token_bytes(32)).decode()

        settings = {
            "server": {
                "listenAddress": ":80",
                "exposedAddress": "https://vpn.denys.me:443",
                "stunPorts": [3478],
                "metricsPort": 9090,
                "healthcheckAddress": ":9000",
                "logLevel": "info",
                "logFile": "console",
                "authSecret": key(),
                "dataDir": "/var/lib/netbird",
                "disableAnonymousMetrics": True,
                "auth": {
                    "issuer": "https://vpn.denys.me/oauth2",
                    "signKeyRefreshEnabled": True,
                    "sessionCookieEncryptionKey": key(),
                    "dashboardRedirectURIs": [
                        "https://vpn.denys.me/nb-auth",
                        "https://vpn.denys.me/nb-silent-auth",
                    ],
                    "cliRedirectURIs": ["http://localhost:53000/"],
                },
                "store": {"engine": "sqlite", "encryptionKey": key()},
            }
        }
        write_private(STATE / "config.json", json.dumps(settings))
    command("systemctl", "start", "podman-netbird-server.service")


def netbird(data):
    instance = wait_for(
        lambda: request(NB_URL, "/instance"), "NetBird did not become ready"
    )
    pat_file = ETC / "bootstrap-pat"
    if instance["setup_required"]:
        owner = request(
            NB_URL,
            "/setup",
            "POST",
            {
                "email": data["email"],
                "name": "Denys",
                "password": data["password"],
                "create_pat": True,
                "pat_expire_in": 7,
            },
        )
        write_private(pat_file, owner["personal_access_token"])
    if not pat_file.exists():
        raise RuntimeError(
            "Owner already exists. Supply a fresh admin PAT in /etc/vpn/bootstrap-pat; never reset the database."
        )
    token = pat_file.read_text().strip()

    def api(path, method="GET", payload=None):
        return request(NB_URL, path, method, payload, token)

    groups = {group["name"]: group for group in api("/groups")}
    for name in ("bao-admins", "bao-server"):
        if name not in groups:
            groups[name] = api("/groups", "POST", {"name": name, "peers": []})
    admins, server = groups["bao-admins"]["id"], groups["bao-server"]["id"]
    policies = api("/policies")
    for policy in policies:
        if policy["name"] == "Default" and policy["enabled"]:
            policy["enabled"] = False
            # NOTE: API responses contain group objects; update requests require IDs.
            for rule in policy["rules"]:
                for field in ("sources", "destinations"):
                    rule[field] = [group["id"] for group in rule.get(field, [])]
            api("/policies/" + policy["id"], "PUT", policy)
    if not any(policy["name"] == "bao-admin-access" for policy in policies):
        api(
            "/policies",
            "POST",
            {
                "name": "bao-admin-access",
                "enabled": True,
                "rules": [
                    {
                        "name": "OpenBao HTTPS",
                        "enabled": True,
                        "action": "accept",
                        "bidirectional": False,
                        "protocol": "tcp",
                        "ports": ["443"],
                        "sources": [admins],
                        "destinations": [server],
                    }
                ],
            },
        )
    if "peer_ip" not in data:
        setup = api(
            "/setup-keys",
            "POST",
            {
                "name": "bao-bootstrap",
                "type": "one-off",
                "expires_in": 86400,
                "auto_groups": [server],
                "usage_limit": 1,
            },
        )
        return {"key": setup["key"], "id": setup["id"]}
    peer = wait_for(
        lambda: next(
            (p for p in api("/peers") if p["ip"] == data["peer_ip"] and p["connected"]),
            None,
        ),
        "Bao peer did not connect",
    )
    if peer["id"] not in [p["id"] for p in groups["bao-server"].get("peers", [])]:
        raise RuntimeError("Bao peer is not in the dedicated server group")
    api(
        "/peers/" + peer["id"],
        "PUT",
        {
            "name": "bao",
            "ssh_enabled": False,
            "login_expiration_enabled": False,
            "inactivity_expiration_enabled": False,
        },
    )
    zones = api("/dns/zones")
    zone = next((zone for zone in zones if zone["domain"] == "bao.vpn.denys.me"), None)
    if zone is None:
        zone = api(
            "/dns/zones",
            "POST",
            {
                "name": "Private OpenBao",
                "domain": "bao.vpn.denys.me",
                "enabled": True,
                "enable_search_domain": False,
                "distribution_groups": [admins, server],
            },
        )
    records = api("/dns/zones/" + zone["id"] + "/records")
    record = next(
        (record for record in records if record["name"] == "bao.vpn.denys.me"), None
    )
    path = "/dns/zones/" + zone["id"] + "/records"
    api(
        path + ("/" + record["id"] if record else ""),
        "PUT" if record else "POST",
        {
            "name": "bao.vpn.denys.me",
            "type": "A",
            "content": peer["ip"],
            "ttl": 60,
        },
    )
    if not (ETC / "proxy.env").exists():
        result = command(
            "podman",
            "exec",
            "netbird-server",
            "/go/bin/netbird-server",
            "admin",
            "token",
            "create",
            "--name",
            "x-proxy",
            "--config",
            "/etc/netbird/config.yaml",
        )
        proxy_token = next(
            line.split(":", 1)[1].strip()
            for line in result.splitlines()
            if line.startswith("Token:")
        )
        write_private(ETC / "proxy.env", "NB_PROXY_TOKEN=" + proxy_token + "\n")
    command("systemctl", "start", "podman-netbird-proxy.service")
    return {
        "peer_ip": peer["ip"],
        "admin_group": "bao-admins",
        "restic_password": (ETC / "restic-password").read_text().strip(),
    }


def revoke_setup(data):
    token = (ETC / "bootstrap-pat").read_text().strip()
    path = "/setup-keys/" + data["id"]
    setup = request(NB_URL, path, token=token)
    return request(
        NB_URL,
        path,
        "PUT",
        {"revoked": True, "auto_groups": setup["auto_groups"]},
        token,
    )


def enroll(data):
    setup_file = ETC / "setup-key"
    write_private(setup_file, data["key"])
    try:
        command(
            "netbird",
            "up",
            "--management-url",
            "https://api.netbird.io:443",
            "--hostname",
            "bao",
            env={**os.environ, "NB_SETUP_KEY_FILE": str(setup_file)},
        )
    finally:
        setup_file.unlink(missing_ok=True)
    status = json.loads(command("netbird", "status", "--json"))
    if not status.get("netbirdIp"):
        raise RuntimeError("NetBird did not report its overlay address")
    return {"peer_ip": str(ipaddress.ip_interface(status["netbirdIp"]).ip)}


def initialize_bao(data):
    command("systemctl", "start", "openbao.service")
    wait_for(
        lambda: request(BAO_URL, "/sys/init"), "OpenBao TLS/DNS did not become ready"
    )
    recovery_file = ETC / "openbao-initialization.json"
    if not request(BAO_URL, "/sys/init")["initialized"]:
        initialized = request(
            BAO_URL, "/sys/init", "PUT", {"recovery_shares": 3, "recovery_threshold": 2}
        )
        write_private(recovery_file, json.dumps(initialized))
    if not recovery_file.exists():
        raise RuntimeError(
            "OpenBao already initialized without bootstrap file; do not initialize or reset it again."
        )
    initialized = json.loads(recovery_file.read_text())
    wait_for(lambda: request(BAO_URL, "/sys/health"), "OpenBao did not auto-unseal")
    if (ETC / "bao-configured").exists():
        return {
            "recovery_keys_b64": initialized["recovery_keys_base64"],
            "restic_password": (ETC / "restic-password").read_text().strip(),
        }
    token = initialized["root_token"]

    def api(path, method="GET", payload=None):
        return request(BAO_URL, path, method, payload, token)

    try:
        api("/auth/token/lookup-self")
    except urllib.error.HTTPError as error:
        if error.code != 403:
            raise
        token = request(
            BAO_URL,
            "/auth/userpass/login/denys",
            "POST",
            {"password": data["password"]},
        )["auth"]["client_token"]

    if "file/" not in api("/sys/audit")["data"]:
        raise RuntimeError("Declarative file audit device is not active")
    api(
        "/sys/policies/acl/admin",
        "PUT",
        {
            "policy": 'path "*" { capabilities = ["create", "read", "update", "delete", "list", "sudo", "patch"] }'
        },
    )
    if "userpass/" not in api("/sys/auth")["data"]:
        api("/sys/auth/userpass", "POST", {"type": "userpass"})
    api(
        "/auth/userpass/users/denys",
        "POST",
        {
            "password": data["password"],
            "token_policies": ["admin"],
            "token_ttl": "1h",
            "token_max_ttl": "8h",
        },
    )
    api(
        "/sys/policies/acl/backup",
        "PUT",
        {
            "policy": 'path "sys/storage/raft/snapshot" { capabilities = ["read"] }\npath "auth/token/renew-self" { capabilities = ["update"] }'
        },
    )
    if not (ETC / "bao-backup-token").exists():
        backup = api(
            "/auth/token/create-orphan",
            "POST",
            {"policies": ["backup"], "period": "72h", "no_default_policy": True},
        )
        write_private(ETC / "bao-backup-token", backup["auth"]["client_token"])
    # NOTE: Verify the replacement login before revoking the bootstrap root token.
    login = request(
        BAO_URL, "/auth/userpass/login/denys", "POST", {"password": data["password"]}
    )
    request(
        BAO_URL, "/auth/token/revoke-self", "POST", {}, login["auth"]["client_token"]
    )
    api("/auth/token/revoke-self", "POST", {})
    write_private(ETC / "bao-configured", "configured\n")
    initialized.pop("root_token", None)
    write_private(recovery_file, json.dumps(initialized))
    return {
        "recovery_keys_b64": initialized["recovery_keys_base64"],
        "restic_password": (ETC / "restic-password").read_text().strip(),
    }


if __name__ == "__main__":
    os.umask(0o077)
    try:
        actions = {"prepare": prepare}
        if host_role() == "vpn":
            actions.update(netbird=netbird, revoke_setup=revoke_setup)
        else:
            actions.update(enroll=enroll, bao=initialize_bao)
        result = actions[sys.argv[1]](json.load(sys.stdin))
        print(json.dumps(result))
    except (
        urllib.error.HTTPError,
        subprocess.CalledProcessError,
        RuntimeError,
        ValueError,
    ) as error:
        # NOTE: Request bodies, command output and exception payloads may contain credentials.
        print(
            f"Bootstrap failed ({type(error).__name__}); inspect service status without sharing secrets.",
            file=sys.stderr,
        )
        sys.exit(1)
