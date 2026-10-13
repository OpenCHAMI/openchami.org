# SPDX-FileCopyrightText: © 2026 OpenCHAMI contributors
# SPDX-License-Identifier: MIT
"""Check published edition menus, legacy links, and discovery exclusions."""
import argparse
import json
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit

import yaml

ROOT = Path(__file__).resolve().parents[1]
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}


class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.links = []
        self.ids = set()
        self.selects = []
        self.options = []
        self.scripts = []
        self.order = []
        self.metas = []
        self.feed(path.read_text())

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        ancestors = [item[1] for item in self.stack]
        if tag == "a":
            self.links.append((attrs, ancestors))
        if tag == "meta":
            self.metas.append(attrs)
        if tag == "select":
            self.selects.append(attrs)
        if tag == "option" and any(parent.get("id") == "document-edition-menu" for parent in ancestors):
            self.options.append(attrs)
        if tag == "script":
            self.scripts.append(attrs)
        if "data-document-toolbar" in attrs:
            self.order.append("toolbar")
        if tag == "h1":
            self.order.append("title")
        if tag not in VOID:
            self.stack.append((tag, attrs))

    def handle_endtag(self, tag):
        for index in range(len(self.stack) - 1, -1, -1):
            if self.stack[index][0] == tag:
                del self.stack[index:]
                break


def metadata(ref, root=ROOT):
    path = root / "content" / ref.lstrip("/")
    source = Path(str(path) + ".md")
    if not source.exists():
        source = path / "_index.md"
    if not source.exists():
        path = root / ".generated/doc-editions/content" / ref.lstrip("/")
        source = Path(str(path) + ".md")
        if not source.exists():
            source = path / "_index.md"
    return yaml.safe_load(source.read_text().split("---", 2)[1])


def url_path(url):
    return urlsplit(url).path.rstrip("/") + "/"


def verify(destination, root=ROOT):
    registry = json.loads((root / ".generated/doc-editions/data/doc_editions.json").read_text())
    search = json.loads((destination / "search-index.json").read_text())
    indexed = {url_path(item["permalink"]) for item in search}
    historical = set()
    count = 0
    for family in registry.values():
        urls = {entry["id"]: entry["url"].rstrip("/") + "/" for entry in family["editions"]}
        for entry in family["editions"]:
            url = urls[entry["id"]]
            page = Page(destination / url.lstrip("/") / "index.html")
            menu = page.options
            assert [url_path(option["value"]) for option in menu] == list(urls.values()), f"Incorrect edition menu: {url}"
            active = [option for option in menu if "selected" in option]
            assert len(active) == 1 and url_path(active[0]["value"]) == url, f"Incorrect current edition: {url}"
            assert any(select.get("id") == "document-edition-menu" and "data-document-edition" in select and select.get("aria-label") for select in page.selects), f"Missing accessible selector: {url}"
            assert page.order.index("toolbar") < page.order.index("title"), f"Selector must appear above title: {url}"
            assert any("doc-editions." in script.get("src", "") and "defer" in script for script in page.scripts), f"Missing edition navigation script: {url}"
            ref_links = [link for link, _ in page.links if "data-edition-github-ref" in link]
            assert len(ref_links) == 1, f"Missing GitHub ref link: {url}"
            if entry["id"] != "latest":
                github_ref = entry.get("tag", entry["commit"])
                assert ref_links[0]["href"].endswith(f"/tree/{github_ref}"), f"Incorrect GitHub ref link: {url}"
                historical.add(url)
                source_metadata = metadata(entry["pageRef"], root)
                assert source_metadata["edition_commit"] == entry["commit"], f"Incorrect Git source commit: {url}"
                source_suffix = f'/blob/{entry["commit"]}/{source_metadata["edition_source"]}'
                assert any(source_suffix in link.get("href", "") for link, _ in page.links), f"Missing immutable Git source link: {url}"
                assert url not in indexed, f"Historical edition in search: {url}"
                assert not any("page-nav" in parent.get("class", "").split() for _, ancestors in page.links for parent in ancestors), f"Historical edition has global previous/next: {url}"
                assert any(url_path(link.get("href", "")) == urls["latest"] for link, ancestors in page.links if any("document-editions" in parent.get("class", "").split() for parent in ancestors)), f"Missing Latest link: {url}"
            else:
                assert "/tree/" in ref_links[0]["href"], f"Missing Latest branch ref: {url}"
                assert url in indexed, f"Latest missing from search: {url}"
            for alias in metadata(entry["pageRef"], root).get("aliases", []):
                redirect = Page(destination / alias.strip("/") / "index.html")
                assert any(meta.get("http-equiv") == "refresh" and url in meta.get("content", "") for meta in redirect.metas), f"Missing alias: {alias}"
            if entry["pageRef"] == "/docs/tutorial" or entry["pageRef"] in {"/docs/editions/tutorial/2025-10-06", "/docs/editions/tutorial/2026-08-06"}:
                assert any(link.get("aria-current") == "page" and url_path(link.get("href", "")) == urls["latest"] for link, ancestors in page.links if any("section-nav" in parent.get("class", "").split() for parent in ancestors)), f"Tutorial sidebar entry not active: {url}"
                assert "26-boot-the-compute-node-with-the-debug-image" in page.ids, f"Tutorial anchor lost: {url}"
                assert any(link.get("href") == "#26-boot-the-compute-node-with-the-debug-image" for link, _ in page.links), f"Tutorial self-link lost: {url}"
            count += 1
    for path in (destination / "docs").rglob("index.html"):
        page = Page(path)
        for link, ancestors in page.links:
            inside_menu = any("document-editions" in parent.get("class", "").split() for parent in ancestors)
            current_url = "/" + path.parent.relative_to(destination).as_posix() + "/"
            target_url = url_path(link.get("href", ""))
            self_link = target_url == current_url
            within_edition = any(current_url.startswith(edition) and target_url.startswith(edition) for edition in historical)
            assert inside_menu or self_link or within_edition or target_url not in historical, f"Snapshot leaked into ordinary navigation/listing: {path}"
    print(f"Verified {count} documentation editions, aliases, anchors, search, and navigation exclusions.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", nargs="?", type=Path, default=ROOT / "public")
    parser.add_argument("--source-root", type=Path, default=ROOT)
    args = parser.parse_args()
    verify(args.destination, args.source_root)
