import base64
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "prepare", Path(__file__).with_name("prepare.py")
)
prepare = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prepare)


def snapshot(lineage, resource_type, name, index=None, module=None):
    instance = {
        "schema_version": 0,
        "attributes": {"id": f"{lineage}-id"},
        "sensitive_attributes": [],
    }
    if index is not None:
        instance["index_key"] = index
    resource = {
        "mode": "managed",
        "type": resource_type,
        "name": name,
        "provider": 'provider["terraform.io/builtin/terraform"]',
        "instances": [instance],
    }
    if module:
        resource["module"] = module
    return {
        "version": 4,
        "terraform_version": "1.11.8",
        "serial": 7,
        "lineage": lineage,
        "outputs": {"existing": {"value": lineage, "type": "string"}},
        "resources": [resource],
    }


class PrepareTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.source = self.directory / "snapshots"
        self.source.mkdir()
        self.destination = self.directory / "candidate"
        fixtures = {
            "main": snapshot("main", "terraform_data", "existing"),
            "bao": snapshot("bao", "terraform_data", "key"),
            "netbird": snapshot(
                "netbird", "terraform_data", "peer", module="module.nested"
            ),
            "railway": snapshot(
                "railway", "terraform_data", "service", index='monitor.with"quote'
            ),
            "ovh-vps": snapshot("ovh", "terraform_data", "host"),
        }
        lookup = snapshot("lookup", "terraform_remote_state", "account")["resources"][0]
        lookup["mode"] = "data"
        fixtures["bao"]["resources"].append(lookup)
        for name, state in fixtures.items():
            (self.source / f"{name}.tfstate").write_text(json.dumps(state))

    def test_moves_every_instance_without_mutating_snapshots(self):
        originals = {path.name: path.read_bytes() for path in self.source.iterdir()}
        prepare.prepare(self.source, self.destination)
        candidate = json.loads((self.destination / "main.tfstate").read_text())
        self.assertEqual(candidate["lineage"], "main")
        self.assertGreater(candidate["serial"], 7)
        self.assertEqual(candidate["outputs"]["existing"]["value"], "main")
        self.assertEqual(
            {
                (resource.get("module"), resource["name"])
                for resource in candidate["resources"]
            },
            {
                (None, "existing"),
                ("module.bao_support", "key"),
                ("module.bao_support", "account"),
                ("module.netbird_access.module.nested", "peer"),
                ("module.railway_services", "service"),
                (None, "host"),
            },
        )
        self.assertEqual(
            {
                instance["attributes"]["id"]
                for resource in candidate["resources"]
                for instance in resource["instances"]
            },
            {"main-id", "bao-id", "lookup-id", "netbird-id", "railway-id", "ovh-id"},
        )
        lookup = next(
            resource
            for resource in candidate["resources"]
            if resource["name"] == "account"
        )
        self.assertEqual(lookup["mode"], "data")
        railway = next(
            resource
            for resource in candidate["resources"]
            if resource["name"] == "service"
        )
        self.assertEqual(railway["instances"][0]["index_key"], 'monitor.with"quote')
        for name in ("bao", "netbird", "railway", "ovh-vps"):
            emptied = json.loads((self.destination / f"{name}.tfstate").read_text())
            original = json.loads(originals[f"{name}.tfstate"])
            self.assertEqual(emptied["resources"], [])
            self.assertEqual(emptied["lineage"], original["lineage"])
            self.assertGreater(emptied["serial"], original["serial"])
        self.assertEqual(
            originals, {path.name: path.read_bytes() for path in self.source.iterdir()}
        )
        self.assertEqual(self.destination.stat().st_mode & 0o777, 0o700)
        self.assertTrue(
            all(
                path.stat().st_mode & 0o077 == 0
                for path in self.destination.glob("*.tfstate*")
            )
        )

    def test_preserves_current_and_deposed_objects_at_their_destination(self):
        expected = []
        for name, module, generations in (
            ("main", None, (None, "dead0001")),
            ("bao", "module.bao_support", (None, "dead0002", "dead0003")),
            ("railway", "module.railway_services", ("dead0004",)),
        ):
            path = self.source / f"{name}.tfstate"
            state = json.loads(path.read_text())
            resource = state["resources"][0]
            instance = resource["instances"][0]
            instance["index_key"] = f"{name}.indexed"
            resource["instances"] = []
            for number, deposed in enumerate(generations):
                object_id = f"{name}-{deposed or 'current'}"
                obj = deepcopy(instance)
                obj.update(
                    schema_version=number,
                    attributes={"id": object_id, "input": f"synthetic-{object_id}"},
                    sensitive_attributes=[[{"type": "get_attr", "value": "input"}]],
                    private=base64.b64encode(object_id.encode()).decode(),
                )
                if deposed:
                    obj["deposed"] = deposed
                resource["instances"].append(obj)
            path.write_text(json.dumps(state))
            destination = deepcopy(resource)
            if module:
                destination["module"] = module
            expected.append(destination)

        originals = {path.name: path.read_bytes() for path in self.source.iterdir()}
        prepare.prepare(self.source, self.destination)
        candidate = json.loads((self.destination / "main.tfstate").read_text())
        self.assertEqual(candidate["lineage"], "main")
        self.assertGreater(candidate["serial"], 7)
        self.assertEqual(len(candidate["resources"]), 6)
        for resource in expected:
            with self.subTest(resource=resource["name"]):
                matches = [
                    actual
                    for actual in candidate["resources"]
                    if (actual.get("module"), actual["type"], actual["name"])
                    == (resource.get("module"), resource["type"], resource["name"])
                ]
                self.assertEqual(len(matches), 1)
                actual = matches[0]
                self.assertEqual(actual["provider"], resource["provider"])
                self.assertCountEqual(actual["instances"], resource["instances"])
        for name in ("bao", "netbird", "railway", "ovh-vps"):
            original = json.loads(originals[f"{name}.tfstate"])
            emptied = json.loads((self.destination / f"{name}.tfstate").read_text())
            self.assertEqual(emptied["resources"], [])
            self.assertEqual(emptied["lineage"], original["lineage"])
            self.assertGreater(emptied["serial"], original["serial"])
        self.assertEqual(
            originals, {path.name: path.read_bytes() for path in self.source.iterdir()}
        )

    def test_rejects_collision_before_creating_candidate(self):
        state = snapshot("main", "terraform_data", "key", module="module.bao_support")
        (self.source / "main.tfstate").write_text(json.dumps(state))
        with self.assertRaisesRegex(ValueError, "collision"):
            prepare.prepare(self.source, self.destination)
        self.assertFalse(self.destination.exists())

    def test_rejects_missing_snapshot_and_reused_destination(self):
        (self.source / "bao.tfstate").unlink()
        with self.assertRaises(FileNotFoundError):
            prepare.prepare(self.source, self.destination)
        self.assertFalse(self.destination.exists())
        self.destination.mkdir()
        with self.assertRaises(FileExistsError):
            prepare.prepare(self.source, self.destination)

    def test_rejects_duplicate_lineage(self):
        state = snapshot("main", "terraform_data", "key")
        (self.source / "bao.tfstate").write_text(json.dumps(state))
        with self.assertRaisesRegex(ValueError, "lineage"):
            prepare.prepare(self.source, self.destination)
        self.assertFalse(self.destination.exists())

    def test_requires_wireguard_retirement_before_consolidation(self):
        for resource_type, name, index in (
            ("random_id", "wg_priv_keys", "server"),
            ("local_file", "generate_wg_nixos_config", None),
            ("local_sensitive_file", "wg_client_config", "phone"),
        ):
            with self.subTest(resource=name):
                state = snapshot("main", resource_type, name, index=index)
                path = self.source / "main.tfstate"
                path.write_text(json.dumps(state))
                original = path.read_bytes()
                destination = self.directory / name
                with self.assertRaisesRegex(ValueError, "Retire WireGuard"):
                    prepare.prepare(self.source, destination)
                self.assertFalse(destination.exists())
                self.assertEqual(path.read_bytes(), original)

    def test_existing_root_addresses_have_complete_moves(self):
        moved = Path(__file__).parents[1] / "moved.tf"
        moves = dict(
            re.findall(
                r"moved\s*\{\s*from\s*=\s*(\S+)\s+to\s*=\s*(\S+)", moved.read_text()
            )
        )
        for resource in (
            "instance",
            "subnet",
            "vcn",
            "route_table",
            "internet_gateway",
            "security_list",
        ):
            address = f"oci_core_{resource}.chunkymonkey"
            self.assertEqual(moves.get(address), f"module.chunkymonkey.{address}")
        for record in (
            "A",
            "www-CNAME",
            "wildcard-CNAME",
            "MX1",
            "MX2",
            "SPF",
            "DKIM1-CNAME",
            "DKIM2-CNAME",
            "DKIM3-CNAME",
        ):
            address = f"cloudflare_dns_record.parked-{record}"
            self.assertEqual(moves.get(address), f"module.parked_domains.{address}")
            self.assertEqual(moves.get(f"cloudflare_record.parked-{record}"), address)
        self.assertEqual(
            moves.get("data.cloudflare_zone.parked"),
            "module.parked_domains.data.cloudflare_zone.parked",
        )

    def test_review_override_selects_local_backend(self):
        (self.directory / "main.tf").write_text("""
terraform {
  backend "http" {
    address = "http://127.0.0.1:1/never-contact-this-backend"
  }
}
""")
        override = Path(__file__).with_name("local-backend_override.tf.example")
        (self.directory / "local-backend_override.tf").write_text(override.read_text())
        prepare.tofu(self.directory, "init", "-reconfigure", "-input=false")
        metadata = json.loads(
            (self.directory / ".terraform/terraform.tfstate").read_text()
        )
        self.assertEqual(metadata["backend"]["type"], "local")
        self.assertEqual(metadata["backend"]["config"]["path"], "candidate.tfstate")

    def test_configured_provider_rebinds_after_module_move(self):
        config = self.directory / "main.tf"
        config.write_text("""
resource "terraform_data" "example" {
  input = "retained"
}
""")
        prepare.tofu(self.directory, "init", "-input=false")
        prepare.tofu(self.directory, "apply", "-auto-approve", "-input=false")
        before = json.loads((self.directory / "terraform.tfstate").read_text())
        resource_id = before["resources"][0]["instances"][0]["attributes"]["id"]
        config.write_text("""
terraform {
  required_providers {
    terraform = { source = "terraform.io/builtin/terraform" }
  }
}
provider "terraform" {
  alias = "ca_central_1"
}
module "bao_support" {
  source = "./module"
  providers = { terraform = terraform.ca_central_1 }
}
""")
        child = self.directory / "module"
        child.mkdir()
        (child / "main.tf").write_text("""
terraform {
  required_providers {
    terraform = { source = "terraform.io/builtin/terraform" }
  }
}
resource "terraform_data" "example" {
  input = "retained"
}
""")
        prepare.tofu(self.directory, "init", "-input=false")
        prepare.tofu(
            self.directory,
            "state",
            "mv",
            "terraform_data.example",
            "module.bao_support.terraform_data.example",
        )
        prepare.tofu(self.directory, "plan", "-input=false", "-out=review.tfplan")
        plan = json.loads(
            "\n".join(prepare.tofu(self.directory, "show", "-json", "review.tfplan"))
        )
        self.assertEqual(
            [change["change"]["actions"] for change in plan["resource_changes"]],
            [["no-op"]],
        )
        prepare.tofu(self.directory, "apply", "-input=false", "review.tfplan")
        after = json.loads((self.directory / "terraform.tfstate").read_text())
        resource = after["resources"][0]
        self.assertEqual(
            resource["provider"],
            'provider["terraform.io/builtin/terraform"].ca_central_1',
        )
        self.assertEqual(resource["instances"][0]["attributes"]["id"], resource_id)


if __name__ == "__main__":
    unittest.main()
