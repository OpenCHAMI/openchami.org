#!/usr/bin/env python3

# SPDX-FileCopyrightText: © 2026 OpenCHAMI contributors
#
# SPDX-License-Identifier: MIT

"""Convert legacy BSS/cloud-init exports to Fabrica resource payloads.

The converter is deliberately offline: it reads JSON or YAML and writes new
payloads without contacting or modifying an OpenCHAMI deployment. JSON support
uses only the Python standard library. YAML support requires PyYAML.
"""

import argparse
import base64
import binascii
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

yaml = None
try:
    import yaml as _yaml  # type: ignore

    yaml = _yaml
    HAVE_YAML = True
except Exception:
    HAVE_YAML = False


class ConversionError(Exception):
    """An input cannot be converted safely."""


class ParseError(ConversionError):
    """An input document cannot be parsed."""


@dataclass
class Report:
    warnings: list[dict[str, Any]] = field(default_factory=list)
    conversions: dict[str, int] = field(default_factory=dict)
    replacements: list[dict[str, str]] = field(default_factory=list)

    def warn(
        self,
        code: str,
        message: str,
        resource: str,
        source: Optional[str] = None,
    ) -> None:
        item = {"code": code, "resource": resource, "message": message}
        if source is not None:
            item["source"] = source
        self.warnings.append(item)

    def replaced(self, resource: str, old: str, new: str) -> None:
        self.replacements.append(
            {"resource": resource, "old": old, "new": new}
        )

    def as_dict(self) -> dict[str, Any]:
        return {
            "conversions": self.conversions,
            "warning_count": len(self.warnings),
            "warnings": self.warnings,
            "replacements": self.replacements,
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="openchami-resources-old2new.py",
        description=(
            "Convert legacy BSS and cloud-init exports into boot-service and "
            "metadata-service payloads. The script never contacts a cluster."
        ),
        epilog=(
            "Examples:\n"
            "  openchami-resources-old2new.py --resource boot \\\n+\n    --metadata-url http://172.16.0.254:8081/metadata-service \\\n+\n    < bss-bootparameters.json > boot-configurations.json\n\n"
            "  openchami-resources-old2new.py \\\n+\n    --bundle migration/export --output-dir migration/converted \\\n+\n    --metadata-url http://172.16.0.254:8081/metadata-service -o yaml"
        ).replace("\n+\n", "\n"),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--resource",
        choices=["boot", "defaults", "groups", "instances"],
        help="Convert one resource type from stdin to stdout.",
    )
    mode.add_argument(
        "--bundle",
        type=Path,
        help="Directory containing the export files created by the guide.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Bundle output directory (required with --bundle).",
    )
    parser.add_argument(
        "-i",
        "--in-format",
        choices=["auto", "json", "yaml"],
        default="auto",
        help="Input format for stdin mode (default: auto).",
    )
    parser.add_argument(
        "-o",
        "--out-format",
        choices=["match", "json", "yaml"],
        default="match",
        help="Output format (default: match each input).",
    )
    parser.add_argument(
        "--metadata-url",
        help="New NoCloud seed base URL ending in /metadata-service.",
    )
    parser.add_argument(
        "--boot-name-prefix",
        default="migrated-boot",
        help="Prefix for generated boot configuration names.",
    )
    parser.add_argument(
        "--defaults-name",
        default="cluster-defaults",
        help="Name for the converted ClusterDefaults resource.",
    )
    parser.add_argument(
        "--stringify-metadata",
        action="store_true",
        help="JSON-stringify non-string legacy group metadata values.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Treat conversion warnings as errors and emit no resources.",
    )
    parser.add_argument(
        "--report",
        type=Path,
        help="Write a JSON report in single-resource mode.",
    )
    args = parser.parse_args()

    if args.bundle and not args.output_dir:
        parser.error("--output-dir is required with --bundle")
    if args.output_dir and not args.bundle:
        parser.error("--output-dir is only valid with --bundle")
    if args.metadata_url:
        args.metadata_url = args.metadata_url.rstrip("/")
        if not args.metadata_url.endswith("/metadata-service"):
            parser.error("--metadata-url must end in /metadata-service")
    if args.out_format == "yaml" and not HAVE_YAML:
        parser.error("YAML output requires PyYAML (python3 -m pip install PyYAML)")
    return args


def parse_document(raw: str, hint: str = "auto") -> tuple[str, Any]:
    if hint in ("auto", "json"):
        try:
            return "json", json.loads(raw)
        except json.JSONDecodeError as error:
            if hint == "json":
                raise ParseError(f"failed to parse JSON: {error}") from error
    if hint in ("auto", "yaml"):
        if not HAVE_YAML:
            raise ParseError(
                "input is not JSON and PyYAML is not installed; install PyYAML "
                "or provide JSON"
            )
        try:
            return "yaml", yaml.safe_load(raw)  # type: ignore[union-attr]
        except Exception as error:
            raise ParseError(f"failed to parse YAML: {error}") from error
    raise ConversionError(f"unsupported input format: {hint}")


def read_document(path: Path) -> tuple[str, Any]:
    hint = "auto"
    if path.suffix.lower() == ".json":
        hint = "json"
    elif path.suffix.lower() in (".yaml", ".yml"):
        hint = "yaml"
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ConversionError(f"failed to read {path}: {error}") from error
    return parse_document(raw, hint)


def serialize_document(obj: Any, fmt: str) -> str:
    if fmt == "json":
        return json.dumps(obj, ensure_ascii=False, indent=2) + "\n"
    if not HAVE_YAML:
        raise ConversionError("YAML output requires PyYAML")

    class PrettySafeDumper(yaml.SafeDumper):  # type: ignore[union-attr]
        """Write IaC-friendly YAML without folding or escaped line breaks."""

    def represent_string(dumper: Any, value: str) -> Any:
        # Templates and other genuinely multiline values are most readable as
        # literal blocks. Long single-line values (kernel parameters and SSH
        # keys in particular) remain single-line scalars.
        style = "|" if "\n" in value else None
        return dumper.represent_scalar(
            "tag:yaml.org,2002:str", value, style=style
        )

    PrettySafeDumper.add_representer(str, represent_string)
    return yaml.dump(  # type: ignore[union-attr]
        obj,
        Dumper=PrettySafeDumper,
        sort_keys=False,
        indent=2,
        default_flow_style=False,
        allow_unicode=True,
        # PyYAML otherwise folds plain scalars at its default 80 columns.
        # A very large width keeps long but intrinsically single-line values
        # on one line without imposing an arbitrary practical limit.
        width=2**31 - 1,
    )


def as_list(data: Any, resource: str, wrapper_keys: tuple[str, ...] = ()) -> list:
    if isinstance(data, dict):
        for key in wrapper_keys:
            if key in data:
                data = data[key]
                break
    if not isinstance(data, list):
        raise ConversionError(f"{resource} input must be an array")
    return data


def slug(value: str, fallback: str) -> str:
    value = re.sub(r"[^a-zA-Z0-9_.-]+", "-", value.strip()).strip("-.")
    return value or fallback


def infer_metadata_url(old_url: str) -> Optional[str]:
    old_url = old_url.rstrip("/")
    if old_url.endswith("/cloud-init"):
        return old_url[: -len("/cloud-init")] + "/metadata-service"
    return None


OLD_SEED_URL = re.compile(r"https?://[^\s'\"]+?/cloud-init/?(?=$|[\s;])")
MAC = re.compile(r"^(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")


def rewrite_seed_urls(
    params: str,
    metadata_url: Optional[str],
    report: Report,
    resource: str,
) -> str:
    def replace(match: re.Match) -> str:
        old = match.group(0).rstrip("/")
        new = metadata_url or infer_metadata_url(old)
        if not new:
            return match.group(0)
        report.replaced(resource, old, new)
        return new

    return OLD_SEED_URL.sub(replace, params)


def convert_boot(
    data: Any,
    report: Report,
    metadata_url: Optional[str],
    name_prefix: str,
) -> list[dict[str, Any]]:
    records = as_list(data, "boot", ("bootparameters", "bootParameters", "items"))
    output = []
    selector_owners: dict[tuple[str, Any], str] = {}
    allowed = {"hosts", "macs", "nids", "kernel", "initrd", "params"}

    for index, raw in enumerate(records, start=1):
        source = f"boot[{index - 1}]"
        if not isinstance(raw, dict):
            raise ConversionError(f"{source} must be an object")
        name = f"{slug(name_prefix, 'migrated-boot')}-{index:03d}"
        converted: dict[str, Any] = {"name": name}

        kernel = raw.get("kernel")
        if not isinstance(kernel, str) or not kernel.strip():
            raise ConversionError(f"{source} has no non-empty kernel")
        converted["kernel"] = kernel

        for key in ("hosts", "macs"):
            values = raw.get(key, [])
            if values is None:
                values = []
            if not isinstance(values, list):
                raise ConversionError(f"{source}.{key} must be an array")
            clean = [str(value) for value in values if value not in (None, "")]
            if key == "macs":
                clean = [value.lower() for value in clean]
                for value in clean:
                    if not MAC.fullmatch(value):
                        report.warn(
                            "invalid-mac",
                            f"MAC address {value!r} may be rejected by boot-service",
                            "boot",
                            source,
                        )
            if clean:
                converted[key] = clean

        nids = raw.get("nids", []) or []
        if not isinstance(nids, list):
            raise ConversionError(f"{source}.nids must be an array")
        converted_nids = []
        for nid in nids:
            try:
                converted_nids.append(int(nid))
            except (TypeError, ValueError):
                report.warn(
                    "invalid-nid",
                    f"NID {nid!r} was omitted because it is not an integer",
                    "boot",
                    source,
                )
        if converted_nids:
            converted["nids"] = converted_nids

        initrd = raw.get("initrd")
        if initrd not in (None, ""):
            if not isinstance(initrd, str):
                raise ConversionError(f"{source}.initrd must be a string")
            converted["initrd"] = initrd

        params = raw.get("params")
        if params not in (None, ""):
            if not isinstance(params, str):
                raise ConversionError(f"{source}.params must be a string")
            converted["params"] = rewrite_seed_urls(
                params, metadata_url, report, name
            )
            if "/cloud-init" in converted["params"]:
                report.warn(
                    "legacy-seed-url",
                    "kernel parameters still contain /cloud-init",
                    "boot",
                    source,
                )

        selectors = sum(
            len(converted.get(key, [])) for key in ("hosts", "macs", "nids")
        )
        if selectors == 0:
            report.warn(
                "catch-all-boot-config",
                "record has no selectors and will be a catch-all configuration",
                "boot",
                source,
            )
        for key in ("hosts", "macs", "nids"):
            for value in converted.get(key, []):
                selector = (key, value)
                if selector in selector_owners:
                    report.warn(
                        "duplicate-selector",
                        f"{key} selector {value!r} also appears in "
                        f"{selector_owners[selector]}",
                        "boot",
                        source,
                    )
                else:
                    selector_owners[selector] = name

        dropped = sorted(set(raw) - allowed)
        if dropped:
            report.warn(
                "dropped-bss-fields",
                f"legacy-only fields were not copied: {', '.join(dropped)}",
                "boot",
                source,
            )
        output.append(converted)

    report.conversions["boot"] = len(output)
    return output


DEFAULT_KEY_MAP = {
    "base-url": "base_url",
    "base_url": "base_url",
    "cloud-provider": "cloud_provider",
    "cloud_provider": "cloud_provider",
    "region": "region",
    "availability-zone": "availability_zone",
    "availability_zone": "availability_zone",
    "cluster-name": "cluster_name",
    "cluster_name": "cluster_name",
    "short-name": "short_name",
    "short_name": "short_name",
    "nid-length": "nid_length",
    "nid_length": "nid_length",
    "public-keys": "public_keys",
    "public_keys": "public_keys",
}


def convert_defaults(
    data: Any,
    report: Report,
    metadata_url: Optional[str],
    name: str,
) -> list[dict[str, Any]]:
    if isinstance(data, list):
        if len(data) != 1:
            raise ConversionError("defaults input must contain exactly one object")
        data = data[0]
    if not isinstance(data, dict):
        raise ConversionError("defaults input must be an object")
    converted: dict[str, Any] = {
        "name": slug(name, "cluster-defaults"),
        "description": "Migrated cluster defaults",
    }
    for old, new in DEFAULT_KEY_MAP.items():
        if old in data and data[old] is not None:
            converted[new] = data[old]

    old_base = converted.get("base_url")
    if metadata_url:
        if old_base and old_base != metadata_url:
            report.replaced("defaults", str(old_base), metadata_url)
        converted["base_url"] = metadata_url
    elif old_base:
        inferred = infer_metadata_url(str(old_base))
        if inferred:
            report.replaced("defaults", str(old_base), inferred)
            converted["base_url"] = inferred
            report.warn(
                "inferred-metadata-url",
                f"inferred metadata-service URL as {inferred!r}; review it",
                "defaults",
            )
    if not converted.get("base_url"):
        raise ConversionError(
            "defaults has no usable base URL; provide --metadata-url"
        )
    if not converted.get("cluster_name"):
        raise ConversionError("defaults has no cluster-name/cluster_name")

    unsupported = [key for key in ("boot-subnet", "wg-subnet") if key in data]
    if unsupported:
        report.warn(
            "unsupported-default-fields",
            f"no modern ClusterDefaults equivalents: {', '.join(unsupported)}",
            "defaults",
        )
    unknown = sorted(set(data) - set(DEFAULT_KEY_MAP) - set(unsupported))
    if unknown:
        report.warn(
            "unknown-default-fields",
            f"unknown fields were not copied: {', '.join(unknown)}",
            "defaults",
        )
    report.conversions["defaults"] = 1
    return [converted]


def group_records(data: Any) -> list[tuple[str, dict[str, Any]]]:
    if isinstance(data, list):
        records = []
        for index, item in enumerate(data):
            if not isinstance(item, dict):
                raise ConversionError(f"groups[{index}] must be an object")
            records.append((str(item.get("name", "")), item))
        return records
    if isinstance(data, dict):
        records = []
        for key, item in data.items():
            if not isinstance(item, dict):
                raise ConversionError(f"group {key!r} must be an object")
            records.append((str(key), item))
        return records
    raise ConversionError("groups input must be an object or array")


def metadata_strings(
    metadata: Any,
    stringify: bool,
    report: Report,
    source: str,
) -> dict[str, str]:
    if metadata is None:
        return {}
    if not isinstance(metadata, dict):
        raise ConversionError(f"{source}.meta-data must be an object")
    output = {}
    for key, value in metadata.items():
        if isinstance(value, str):
            output[str(key)] = value
        elif stringify:
            output[str(key)] = json.dumps(
                value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
            )
            report.warn(
                "stringified-group-metadata",
                f"meta-data value {key!r} was JSON-stringified",
                "groups",
                source,
            )
        else:
            raise ConversionError(
                f"{source}.meta-data[{key!r}] is not a string; rerun with "
                "--stringify-metadata after reviewing the value"
            )
    return output


def decode_template(file_data: Any, source: str) -> str:
    if not isinstance(file_data, dict):
        raise ConversionError(f"{source}.file must be an object")
    content = file_data.get("content")
    if not isinstance(content, str) or not content:
        raise ConversionError(f"{source}.file.content must be a non-empty string")
    encoding = str(file_data.get("encoding", "plain") or "plain").lower()
    if encoding == "plain":
        return content
    if encoding != "base64":
        raise ConversionError(f"{source}.file.encoding {encoding!r} is unsupported")
    try:
        decoded = base64.b64decode(re.sub(r"\s+", "", content), validate=True)
    except (binascii.Error, ValueError) as error:
        raise ConversionError(f"{source}.file.content is invalid base64") from error
    try:
        return decoded.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ConversionError(
            f"{source}.file.content is not UTF-8 text after base64 decoding"
        ) from error


def convert_groups(
    data: Any,
    report: Report,
    stringify_metadata: bool,
) -> list[dict[str, Any]]:
    output = []
    names = set()
    allowed = {"name", "description", "meta-data", "metaData", "file", "versions"}
    for index, (key, raw) in enumerate(group_records(data)):
        source = f"group[{key or index}]"
        name = slug(str(raw.get("name") or key), f"migrated-group-{index + 1:03d}")
        if name in names:
            raise ConversionError(f"duplicate converted group name {name!r}")
        names.add(name)
        converted: dict[str, Any] = {
            "name": name,
            "template": decode_template(raw.get("file"), source),
        }
        if raw.get("description") not in (None, ""):
            converted["description"] = str(raw["description"])
        metadata = raw.get("meta-data", raw.get("metaData"))
        converted_metadata = metadata_strings(
            metadata, stringify_metadata, report, source
        )
        if converted_metadata:
            converted["metaData"] = converted_metadata
        if "versions" in raw:
            report.warn(
                "dropped-group-versions",
                "legacy template version history is retained only in the export",
                "groups",
                source,
            )
        unknown = sorted(set(raw) - allowed)
        if unknown:
            report.warn(
                "unknown-group-fields",
                f"unknown fields were not copied: {', '.join(unknown)}",
                "groups",
                source,
            )
        output.append(converted)
    report.conversions["groups"] = len(output)
    return output


INSTANCE_KEY_MAP = {
    "instance-id": "instance_id",
    "instance_id": "instance_id",
    "local-hostname": "local_hostname",
    "local_hostname": "local_hostname",
    "hostname": "hostname",
    "cloud-init-base-url": "cloud_init_base_url",
    "cloud_init_base_url": "cloud_init_base_url",
    "public-keys": "public_keys",
    "public_keys": "public_keys",
    "description": "description",
}


def convert_instances(
    data: Any,
    report: Report,
    metadata_url: Optional[str],
) -> list[dict[str, Any]]:
    if isinstance(data, dict):
        if any(key in data for key in ("id", "instance-id", "instance_id")):
            records = [(None, data)]
        else:
            records = list(data.items())
    elif isinstance(data, list):
        records = [(None, item) for item in data]
    else:
        raise ConversionError("instances input must be an object or array")

    output = []
    unsupported = {
        "cluster-name",
        "cluster_name",
        "region",
        "availability-zone",
        "availability_zone",
        "cloud-provider",
        "cloud_provider",
        "instance-type",
        "instance_type",
    }
    for index, (map_key, raw) in enumerate(records):
        source = f"instance[{map_key if map_key is not None else index}]"
        if not isinstance(raw, dict):
            raise ConversionError(f"{source} must be an object")
        instance_id = raw.get("instance-id", raw.get("instance_id", raw.get("id", map_key)))
        if not isinstance(instance_id, str) or not instance_id:
            raise ConversionError(f"{source} has no instance ID")
        converted: dict[str, Any] = {
            "name": slug(str(raw.get("name") or raw.get("id") or map_key or instance_id), instance_id),
            "instance_id": instance_id,
        }
        for old, new in INSTANCE_KEY_MAP.items():
            if old in raw and raw[old] is not None:
                converted[new] = raw[old]
        if metadata_url:
            old_url = converted.get("cloud_init_base_url")
            if old_url and old_url != metadata_url:
                report.replaced(source, str(old_url), metadata_url)
            converted["cloud_init_base_url"] = metadata_url
        elif converted.get("cloud_init_base_url"):
            inferred = infer_metadata_url(str(converted["cloud_init_base_url"]))
            if inferred:
                converted["cloud_init_base_url"] = inferred
                report.replaced(source, str(raw.get("cloud-init-base-url", "")), inferred)
        present_unsupported = sorted(set(raw) & unsupported)
        if present_unsupported:
            report.warn(
                "unsupported-instance-fields",
                "no modern per-instance equivalents: "
                + ", ".join(present_unsupported),
                "instances",
                source,
            )
        known = set(INSTANCE_KEY_MAP) | unsupported | {"id", "name"}
        unknown = sorted(set(raw) - known)
        if unknown:
            report.warn(
                "unknown-instance-fields",
                f"unknown fields were not copied: {', '.join(unknown)}",
                "instances",
                source,
            )
        output.append(converted)
    report.conversions["instances"] = len(output)
    return output


def convert_resource(
    resource: str,
    data: Any,
    report: Report,
    args: argparse.Namespace,
) -> Any:
    if resource == "boot":
        return convert_boot(
            data, report, args.metadata_url, args.boot_name_prefix
        )
    if resource == "defaults":
        return convert_defaults(
            data, report, args.metadata_url, args.defaults_name
        )
    if resource == "groups":
        return convert_groups(data, report, args.stringify_metadata)
    if resource == "instances":
        return convert_instances(data, report, args.metadata_url)
    raise ConversionError(f"unsupported resource type: {resource}")


BUNDLE_FILES = {
    "boot": "bss-bootparameters",
    "defaults": "cloud-init-defaults",
    "groups": "cloud-init-groups",
    "instances": "cloud-init-instance-overrides",
}


OUTPUT_FILES = {
    "boot": "boot-configurations",
    "defaults": "cluster-defaults",
    "groups": "groups",
    "instances": "instance-info",
}


def find_bundle_file(directory: Path, stem: str) -> Optional[Path]:
    for suffix in (".json", ".yaml", ".yml"):
        candidate = directory / f"{stem}{suffix}"
        if candidate.is_file():
            return candidate
    return None


def derive_bundle_metadata_url(directory: Path) -> Optional[str]:
    defaults_path = find_bundle_file(directory, BUNDLE_FILES["defaults"])
    if not defaults_path:
        return None
    _, defaults = read_document(defaults_path)
    if isinstance(defaults, list) and len(defaults) == 1:
        defaults = defaults[0]
    if not isinstance(defaults, dict):
        return None
    old_url = defaults.get("base-url", defaults.get("base_url"))
    return infer_metadata_url(str(old_url)) if old_url else None


def run_single(args: argparse.Namespace) -> int:
    raw = sys.stdin.read()
    input_format, data = parse_document(raw, args.in_format)
    report = Report()
    converted = convert_resource(args.resource, data, report, args)
    if args.strict and report.warnings:
        raise ConversionError(
            f"strict mode rejected {len(report.warnings)} conversion warning(s)"
        )
    output_format = input_format if args.out_format == "match" else args.out_format
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            json.dumps(report.as_dict(), ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    sys.stdout.write(serialize_document(converted, output_format))
    sys.stderr.write(
        f"Converted {len(converted)} {args.resource} resource(s); "
        f"{len(report.warnings)} warning(s).\n"
    )
    return 0


def run_bundle(args: argparse.Namespace) -> int:
    if not args.bundle.is_dir():
        raise ConversionError(f"bundle directory does not exist: {args.bundle}")
    report = Report()
    if args.metadata_url is None:
        args.metadata_url = derive_bundle_metadata_url(args.bundle)
        if args.metadata_url:
            report.warn(
                "inferred-metadata-url",
                f"inferred metadata-service URL as {args.metadata_url!r}; review it",
                "bundle",
            )
    staged: list[tuple[Path, str]] = []

    for resource, stem in BUNDLE_FILES.items():
        path = find_bundle_file(args.bundle, stem)
        if path is None:
            if resource == "instances":
                report.warn(
                    "missing-optional-instance-export",
                    "no raw instance override export was supplied",
                    "instances",
                )
                continue
            raise ConversionError(
                f"bundle is missing {stem}.json, {stem}.yaml, or {stem}.yml"
            )
        input_format, data = read_document(path)
        converted = convert_resource(resource, data, report, args)
        output_format = input_format if args.out_format == "match" else args.out_format
        suffix = ".yaml" if output_format == "yaml" else ".json"
        staged.append(
            (
                args.output_dir / f"{OUTPUT_FILES[resource]}{suffix}",
                serialize_document(converted, output_format),
            )
        )

    if args.strict and report.warnings:
        raise ConversionError(
            f"strict mode rejected {len(report.warnings)} conversion warning(s)"
        )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for path, content in staged:
        path.write_text(content, encoding="utf-8")
    report_path = args.output_dir / "migration-report.json"
    report_path.write_text(
        json.dumps(report.as_dict(), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    total = sum(report.conversions.values())
    sys.stderr.write(
        f"Converted {total} resource(s) into {args.output_dir}; "
        f"{len(report.warnings)} warning(s). Review {report_path}.\n"
    )
    return 0


def main() -> int:
    try:
        args = parse_args()
        if args.bundle:
            return run_bundle(args)
        return run_single(args)
    except ParseError as error:
        sys.stderr.write(f"Parse failed: {error}\n")
        return 2
    except ConversionError as error:
        sys.stderr.write(f"Conversion failed: {error}\n")
        return 3
    except (OSError, UnicodeError) as error:
        sys.stderr.write(f"I/O failed: {error}\n")
        return 2


if __name__ == "__main__":
    sys.exit(main())
