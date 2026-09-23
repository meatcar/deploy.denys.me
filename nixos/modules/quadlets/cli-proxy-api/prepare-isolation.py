"""Use production routing in the VM with local backends and no ACME account."""

import json
import sys
from pathlib import Path

import yaml

out = Path(sys.argv[1])
(out / "dynamic").mkdir(parents=True)
static = yaml.safe_load(Path(sys.argv[2]).read_text())
del static["certificatesResolvers"]
static["entryPoints"]["web"]["address"] = ":8080"
static["entryPoints"]["websecure"]["address"] = ":8443"
static["providers"] = {"file": {"directory": str(out / "dynamic")}}
(out / "static.json").write_text(json.dumps(static))

app = yaml.safe_load(Path(sys.argv[3]).read_text())
for service in app["http"]["services"].values():
    service["loadBalancer"]["servers"] = [{"url": "http://127.0.0.1:8317"}]
cpa = json.loads(Path(sys.argv[4]).read_text())
for name, config in [("app", app), ("cpa", cpa)]:
    for router in config["http"]["routers"].values():
        router["tls"] = {}
    (out / "dynamic" / (name + ".yml")).write_text(json.dumps(config))
