#!/usr/bin/env python3
"""No-dependency structural checks for the PaceBack static submission site."""

from __future__ import annotations

from collections import Counter
import hashlib
from html.parser import HTMLParser
from pathlib import Path
import re
import sys
from urllib.parse import urlparse


SITE_ROOT = Path(__file__).resolve().parents[1]
HTML_PATH = SITE_ROOT / "index.html"
CSS_PATH = SITE_ROOT / "styles.css"
JS_PATH = SITE_ROOT / "app.js"
ALLOWED_EXTERNAL_LINK_HOSTS = {
    "hack-for-humanity-summer-26.devpost.com",
    "humanfactors.jmir.org",
}
EXPECTED_IOS_CAPTURE_SHA256 = {
    "assets/paceback-ios-evidence-query.jpg": "23e6eb62515294c76ea62e855070c9de998f651dd74a774b79456ba8d4c7aa1d",
    "assets/paceback-ios-evidence-result.jpg": "1374d1cf6124eb75f44f52aa4b9c13281b47782b5d34052352542d2e9272c7c2",
    "assets/paceback-ios-setup-privacy.jpg": "913b38e2d028257d659a24852373e72c8f6d6df5b871371ea01a1ec565207738",
    "assets/paceback-ios-setup-top.jpg": "c3faf850df2eb3c82733040d30d0fa98bc008d34c2a77acd8248df41395541df",
    "assets/paceback-ios-today.jpg": "56b4d120cb11ced044c74cbde3e8032210901ba37807546f3166e5ed42b8faa8",
}


class SiteParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.tags: Counter[str] = Counter()
        self.ids: list[str] = []
        self.refs: list[tuple[str, str, str]] = []
        self.images: list[dict[str, str]] = []
        self.buttons: list[dict[str, str]] = []
        self.links: list[dict[str, str]] = []
        self.h1_count = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = {key: value or "" for key, value in attrs}
        self.tags[tag] += 1
        if attributes.get("id"):
            self.ids.append(attributes["id"])
        if tag == "h1":
            self.h1_count += 1
        for attribute in ("href", "src"):
            if attributes.get(attribute):
                self.refs.append((tag, attribute, attributes[attribute]))
        if tag == "img":
            self.images.append(attributes)
        if tag == "button":
            self.buttons.append(attributes)
        if tag == "a":
            self.links.append(attributes)


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def main() -> int:
    errors: list[str] = []
    for path in (HTML_PATH, CSS_PATH, JS_PATH):
        if not path.is_file():
            fail(errors, f"missing required file: {path.relative_to(SITE_ROOT)}")

    if errors:
        return report(errors)

    html = HTML_PATH.read_text(encoding="utf-8")
    css = CSS_PATH.read_text(encoding="utf-8")
    js = JS_PATH.read_text(encoding="utf-8")

    parser = SiteParser()
    parser.feed(html)
    parser.close()

    if parser.h1_count != 1:
        fail(errors, f"expected exactly one h1, found {parser.h1_count}")

    for landmark in ("header", "main", "footer", "nav"):
        if parser.tags[landmark] == 0:
            fail(errors, f"missing semantic landmark: {landmark}")

    duplicate_ids = sorted(name for name, count in Counter(parser.ids).items() if count > 1)
    if duplicate_ids:
        fail(errors, f"duplicate ids: {', '.join(duplicate_ids)}")

    known_ids = set(parser.ids)
    external_links = 0
    local_references = 0
    for tag, attribute, reference in parser.refs:
        if reference.startswith("https://"):
            parsed = urlparse(reference)
            if tag != "a" or attribute != "href":
                fail(errors, f"external resources are forbidden; only approved links may be external: {reference}")
            elif parsed.hostname not in ALLOWED_EXTERNAL_LINK_HOSTS:
                fail(errors, f"external link host is not approved: {reference}")
            else:
                external_links += 1
            continue

        if reference.startswith(("http://", "//", "data:")):
            fail(errors, f"insecure, protocol-relative, or embedded {attribute} on <{tag}>: {reference}")
            continue

        if reference.startswith("#"):
            if reference[1:] not in known_ids:
                fail(errors, f"fragment points to missing id: {reference}")
            local_references += 1
            continue

        path_part = reference.split("#", maxsplit=1)[0].split("?", maxsplit=1)[0]
        if path_part and not (SITE_ROOT / path_part).resolve().exists():
            fail(errors, f"local reference does not exist: {reference}")
        local_references += 1

    for index, image in enumerate(parser.images, start=1):
        if "alt" not in image:
            fail(errors, f"image {index} has no alt attribute")
        if not image.get("width") or not image.get("height"):
            fail(errors, f"image {index} is missing intrinsic dimensions")

        source = image.get("src", "")
        if source and not source.startswith(("http://", "https://", "//", "data:")):
            image_path = (SITE_ROOT / source).resolve()
            if image_path.is_file() and image_path.stat().st_size > 400_000:
                fail(errors, f"image {index} exceeds the 400 KB site budget: {image_path.name}")

    for index, button in enumerate(parser.buttons, start=1):
        if button.get("type") != "button":
            fail(errors, f"button {index} must declare type=button")
        if any(name in button.get("class", "").split() for name in ("age-stop", "route-button", "setup-stage")):
            target = button.get("aria-controls", "")
            if not target or target not in known_ids:
                fail(errors, f"interactive receipt button {index} must control an existing element")
            if button.get("aria-pressed") not in {"true", "false"}:
                fail(errors, f"interactive receipt button {index} must expose aria-pressed")

    external_link_urls = {
        link.get("href", "")
        for link in parser.links
        if link.get("href", "").startswith("https://")
    }
    required_external_links = {
        "https://humanfactors.jmir.org/2019/2/e12135",
        "https://humanfactors.jmir.org/2025/1/e75323",
        "https://hack-for-humanity-summer-26.devpost.com/rules",
    }
    missing_external_links = sorted(required_external_links - external_link_urls)
    if missing_external_links:
        fail(errors, f"missing approved design-input links: {', '.join(missing_external_links)}")

    required_html_markers = (
        'class="skip-link"',
        'id="main" tabindex="-1"',
        'aria-live="polite"',
        "Research prototype",
        "does not diagnose",
        "Native Mac + iPhone",
        "157,716,998 bytes",
        "357,919,352 bytes",
        "Ed25519",
        "SHA-256",
        "Ready offline",
        "public trusted evidence only",
        "seven bundled curated",
        "no plan RAG",
        "388 ms",
        "not a latency benchmark",
        "Research-informed does not mean research-validated.",
        "assets/paceback-ios-setup-top.jpg",
        "assets/paceback-ios-setup-privacy.jpg",
        "assets/paceback-ios-today.jpg",
        "assets/paceback-ios-evidence-query.jpg",
        "assets/paceback-ios-evidence-result.jpg",
        "swaps BGE dense retrieval and MiniLM reranking together",
        "662/662",
        "51.53 ms",
        "7.09 ms",
        "full_real_models_unreviewed_unmeasured_2026-08-25-v2.summary.json",
        "full_fallback_unreviewed_unmeasured_2026-08-25-v3.summary.json",
    )
    for marker in required_html_markers:
        if marker not in html:
            fail(errors, f"missing required content/accessibility marker: {marker}")

    required_css_markers = (
        "@media (min-width: 48rem)",
        "@media (min-width: 64rem)",
        "@media (min-width: 80rem)",
        "@media (prefers-reduced-motion: reduce)",
        "@media (forced-colors: active)",
        ":focus-visible",
        "min-height: 2.75rem",
        "overflow-x: clip",
    )
    for marker in required_css_markers:
        if marker not in css:
            fail(errors, f"missing responsive/accessibility CSS marker: {marker}")

    if re.search(r"@import\s+url|url\(\s*['\"]?https?://", css, re.IGNORECASE):
        fail(errors, "CSS must not import or request external resources")

    forbidden_runtime_apis = ("fetch(", "XMLHttpRequest", "WebSocket", "EventSource", "sendBeacon")
    for api in forbidden_runtime_apis:
        if api in js:
            fail(errors, f"runtime network API is forbidden: {api}")

    icon = SITE_ROOT / "assets" / "paceback-icon-512.png"
    if not icon.is_file():
        fail(errors, "optimized PaceBack icon is missing")
    elif icon.stat().st_size > 400_000:
        fail(errors, f"optimized icon is too large: {icon.stat().st_size} bytes")

    for relative_path, expected_digest in EXPECTED_IOS_CAPTURE_SHA256.items():
        capture_path = SITE_ROOT / relative_path
        if not capture_path.is_file():
            fail(errors, f"expected iOS capture is missing: {relative_path}")
            continue
        actual_digest = hashlib.sha256(capture_path.read_bytes()).hexdigest()
        if actual_digest != expected_digest:
            fail(errors, f"iOS capture hash mismatch: {relative_path}")

    return report(
        errors,
        parser=parser,
        icon=icon,
        local_references=local_references,
        external_links=external_links,
    )


def report(
    errors: list[str],
    parser: SiteParser | None = None,
    icon: Path | None = None,
    local_references: int = 0,
    external_links: int = 0,
) -> int:
    if errors:
        print("PaceBack site checks: FAILED", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    assert parser is not None and icon is not None
    print("PaceBack site checks: PASS")
    print(f"  semantic tags checked: {sum(parser.tags.values())}")
    print(f"  unique ids: {len(set(parser.ids))}")
    print(f"  local references: {local_references}")
    print(f"  approved external design-input links: {external_links}")
    print(f"  images with alt + intrinsic size: {len(parser.images)}")
    print(f"  simulator capture hashes verified: {len(EXPECTED_IOS_CAPTURE_SHA256)}")
    print(f"  optimized icon: {icon.stat().st_size} bytes")
    print("  runtime network APIs: none")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
