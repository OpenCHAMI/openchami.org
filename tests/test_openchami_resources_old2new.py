# SPDX-FileCopyrightText: © 2026 OpenCHAMI contributors
#
# SPDX-License-Identifier: MIT

import json
import subprocess
import sys
import tempfile
import types
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "static" / "scripts" / "openchami-resources-old2new.py"
old2new = types.ModuleType("old2new")
old2new.__file__ = str(SCRIPT)
sys.modules[old2new.__name__] = old2new
exec(
    compile(SCRIPT.read_text(encoding="utf-8"), str(SCRIPT), "exec"),
    old2new.__dict__,
)


class ConversionTests(unittest.TestCase):
    @unittest.skipUnless(old2new.HAVE_YAML, "PyYAML is not installed")
    def test_yaml_output_preserves_long_and_multiline_strings(self):
        params = (
            "nomodeset ro "
            "root=live:http://172.16.0.254:7070/boot-images/compute/debug/"
            "rocky9.8-compute-debug-rocky9 ip=dhcp overlayroot=tmpfs "
            "overlayroot_cfgdisk=disabled apparmor=0 selinux=0 "
            "console=ttyS0,115200 ip6=off cloud-init=enabled "
            "ds=nocloud-net;s=http://172.16.0.254:8081/metadata-service"
        )
        public_key = (
            "ssh-ed25519 "
            "AAAAC3NzaC1lZDI1NTE5AAAAIIbnaYB/7+VubYVBJ0K1JLG3OfHWGYli4stOc+ODv3R7 "
            "rocky@db-head"
        )
        template = (
            "## template: jinja\n"
            "#cloud-config\n"
            "merge_how:\n"
            "- name: list\n"
            "  settings: [append]\n"
            "users:\n"
            "  - name: root\n"
            "    ssh_authorized_keys: "
            "{{ ds.meta_data.instance_data.v1.public_keys }}\n"
            "disable_root: false\n"
        )
        document = [
            {
                "name": "compute",
                "params": params,
                "public_keys": [public_key],
                "template": template,
            }
        ]

        rendered = old2new.serialize_document(document, "yaml")

        params_lines = [
            line for line in rendered.splitlines() if line.startswith("  params:")
        ]
        self.assertEqual(len(params_lines), 1)
        self.assertIn(params, params_lines[0])
        key_lines = [
            line for line in rendered.splitlines() if "ssh-ed25519" in line
        ]
        self.assertEqual(len(key_lines), 1)
        self.assertIn(public_key, key_lines[0])
        self.assertIn("  template: |", rendered)
        self.assertIn("    ## template: jinja\n    #cloud-config", rendered)
        self.assertNotIn('template: "', rendered)
        self.assertNotIn("\\n", rendered)
        self.assertEqual(old2new.yaml.safe_load(rendered), document)

    def test_convert_boot_rewrites_url_and_reports_dropped_fields(self):
        report = old2new.Report()
        output = old2new.convert_boot(
            [
                {
                    "macs": ["52:54:00:BE:EF:01"],
                    "nids": ["7", "bad"],
                    "kernel": "http://images/vmlinuz",
                    "initrd": "http://images/initrd",
                    "params": (
                        "ip=dhcp ds=nocloud-net;"
                        "s=http://172.16.0.254:8081/cloud-init"
                    ),
                    "cloud-init": {"user-data": "ignored"},
                    "meta": {"comment": "ignored"},
                }
            ],
            report,
            "http://172.16.0.254:8081/metadata-service",
            "migrated-boot",
        )

        self.assertEqual(output[0]["name"], "migrated-boot-001")
        self.assertEqual(output[0]["macs"], ["52:54:00:be:ef:01"])
        self.assertEqual(output[0]["nids"], [7])
        self.assertIn("/metadata-service", output[0]["params"])
        self.assertNotIn("cloud-init", output[0])
        codes = {warning["code"] for warning in report.warnings}
        self.assertIn("invalid-nid", codes)
        self.assertIn("dropped-bss-fields", codes)

    def test_convert_boot_detects_duplicate_selector(self):
        report = old2new.Report()
        records = [
            {"macs": ["52:54:00:be:ef:01"], "kernel": "/vmlinuz"},
            {"macs": ["52:54:00:be:ef:01"], "kernel": "/debug-vmlinuz"},
        ]
        old2new.convert_boot(records, report, None, "boot")
        self.assertIn(
            "duplicate-selector", {item["code"] for item in report.warnings}
        )

    def test_convert_defaults_renames_fields(self):
        report = old2new.Report()
        output = old2new.convert_defaults(
            {
                "base-url": "http://host:8081/cloud-init",
                "cloud-provider": "OpenCHAMI",
                "availability-zone": "lab-a",
                "cluster-name": "demo",
                "short-name": "de",
                "nid-length": 4,
                "public-keys": ["ssh-ed25519 AAAA test"],
                "boot-subnet": "172.16.0.0/24",
            },
            report,
            None,
            "cluster-defaults",
        )
        spec = output[0]
        self.assertEqual(spec["base_url"], "http://host:8081/metadata-service")
        self.assertEqual(spec["cluster_name"], "demo")
        self.assertEqual(spec["nid_length"], 4)
        self.assertNotIn("boot-subnet", spec)
        codes = {warning["code"] for warning in report.warnings}
        self.assertIn("inferred-metadata-url", codes)
        self.assertIn("unsupported-default-fields", codes)

    def test_convert_plain_and_base64_groups(self):
        plain = "#cloud-config\nhostname: {{ hostname }}\n"
        encoded = old2new.base64.b64encode(plain.encode()).decode()
        report = old2new.Report()
        output = old2new.convert_groups(
            {
                "compute": {
                    "name": "compute",
                    "description": "Compute nodes",
                    "meta-data": {"scheduler": "slurm"},
                    "file": {"content": plain, "encoding": "plain"},
                },
                "login": {
                    "file": {"content": encoded, "encoding": "base64"},
                },
            },
            report,
            False,
        )
        self.assertEqual(output[0]["template"], plain)
        self.assertEqual(output[0]["metaData"], {"scheduler": "slurm"})
        self.assertEqual(output[1]["template"], plain)

    def test_group_non_string_metadata_requires_opt_in(self):
        data = {
            "compute": {
                "meta-data": {"partitions": ["debug", "batch"]},
                "file": {"content": "#cloud-config\n", "encoding": "plain"},
            }
        }
        with self.assertRaises(old2new.ConversionError):
            old2new.convert_groups(data, old2new.Report(), False)

        report = old2new.Report()
        output = old2new.convert_groups(data, report, True)
        self.assertEqual(
            output[0]["metaData"]["partitions"], '["debug","batch"]'
        )
        self.assertEqual(report.warnings[0]["code"], "stringified-group-metadata")

    def test_invalid_base64_is_rejected(self):
        data = {
            "compute": {
                "file": {"content": "not base64!", "encoding": "base64"}
            }
        }
        with self.assertRaises(old2new.ConversionError):
            old2new.convert_groups(data, old2new.Report(), False)

    def test_convert_instances_reports_unsupported_fields(self):
        report = old2new.Report()
        output = old2new.convert_instances(
            [
                {
                    "id": "x1000c0s0b0n0",
                    "local-hostname": "compute01",
                    "cloud-init-base-url": "http://host/cloud-init",
                    "instance-type": "compute",
                }
            ],
            report,
            "http://host/metadata-service",
        )
        self.assertEqual(output[0]["instance_id"], "x1000c0s0b0n0")
        self.assertEqual(output[0]["local_hostname"], "compute01")
        self.assertNotIn("instance_type", output[0])
        self.assertIn(
            "unsupported-instance-fields",
            {warning["code"] for warning in report.warnings},
        )


class CommandTests(unittest.TestCase):
    def run_script(self, *args, input_data=""):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            input=input_data,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_stdin_json_conversion(self):
        result = self.run_script(
            "--resource",
            "boot",
            input_data=json.dumps([{"kernel": "/vmlinuz", "nids": ["42"]}]),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)
        self.assertEqual(output[0]["nids"], [42])

    def test_strict_mode_emits_no_document(self):
        result = self.run_script(
            "--resource",
            "boot",
            "--strict",
            input_data=json.dumps([{"kernel": "/vmlinuz"}]),
        )
        self.assertEqual(result.returncode, 3)
        self.assertEqual(result.stdout, "")
        self.assertIn("strict mode rejected", result.stderr)

    def test_bundle_conversion_and_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            export = root / "export"
            converted = root / "converted"
            export.mkdir()
            source_documents = {
                "bss-bootparameters.json": [
                    {"kernel": "/vmlinuz", "nids": ["1"]}
                ],
                "cloud-init-defaults.json": {
                    "base-url": "http://host/cloud-init",
                    "cluster-name": "demo",
                },
                "cloud-init-groups.json": {
                    "compute": {
                        "file": {
                            "content": "#cloud-config\n",
                            "encoding": "plain",
                        }
                    }
                },
            }
            for name, document in source_documents.items():
                (export / name).write_text(json.dumps(document), encoding="utf-8")

            result = self.run_script(
                "--bundle",
                str(export),
                "--output-dir",
                str(converted),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((converted / "boot-configurations.json").is_file())
            self.assertTrue((converted / "cluster-defaults.json").is_file())
            self.assertTrue((converted / "groups.json").is_file())
            report = json.loads(
                (converted / "migration-report.json").read_text(encoding="utf-8")
            )
            self.assertEqual(report["conversions"]["boot"], 1)
            self.assertIn(
                "missing-optional-instance-export",
                {warning["code"] for warning in report["warnings"]},
            )
            self.assertEqual(
                json.loads((export / "bss-bootparameters.json").read_text()),
                source_documents["bss-bootparameters.json"],
            )


if __name__ == "__main__":
    unittest.main()
