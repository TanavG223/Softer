#!/usr/bin/env python3
"""Dependency-free structural and claim checks for the Softer static site."""

from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
import re
import sys
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
FILES = [ROOT / name for name in ("index.html", "styles.css", "app.js", "README.md")]
REQUIRED_ACTIONS = {"tel:988", "sms:988", "tel:911"}
ALLOWED_HOSTS = {
    "988lifeline.org", "findahelpline.com", "finchcare.com", "github.com",
    "howwefeel.org", "pmc.ncbi.nlm.nih.gov", "pubmed.ncbi.nlm.nih.gov",
    "tdr.who.int", "truluv.ai", "www.blockblast.com", "www.nccih.nih.gov",
    "www.nimh.nih.gov", "www.who.int",
}


class Parser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tags = Counter()
        self.ids = []
        self.refs = []
        self.images = []
        self.buttons = []
        self.invalid_anchor_roles = []

    def handle_starttag(self, tag, attrs):
        values = {key: value or "" for key, value in attrs}
        self.tags[tag] += 1
        if values.get("id"):
            self.ids.append(values["id"])
        for attribute in ("href", "src"):
            if values.get(attribute):
                self.refs.append((tag, attribute, values[attribute]))
        if tag == "img":
            self.images.append(values)
        if tag == "button":
            self.buttons.append(values)
        if tag == "a" and values.get("role"):
            self.invalid_anchor_roles.append(values["role"])


def main():
    errors = []
    for path in FILES:
        if not path.is_file():
            errors.append(f"missing {path.name}")
    if errors:
        return report(errors)

    html, css, js, readme = (path.read_text(encoding="utf-8") for path in FILES)
    public = (html + "\n" + readme).lower()
    parser = Parser()
    parser.feed(html)

    if parser.tags["h1"] != 1:
        errors.append(f"expected one h1, found {parser.tags['h1']}")
    for landmark in ("header", "nav", "main", "footer"):
        if not parser.tags[landmark]:
            errors.append(f"missing {landmark} landmark")
    duplicates = [value for value, count in Counter(parser.ids).items() if count > 1]
    if duplicates:
        errors.append("duplicate ids: " + ", ".join(sorted(duplicates)))

    known_ids = set(parser.ids)
    actions = set()
    for tag, attribute, ref in parser.refs:
        if ref.startswith(("tel:", "sms:")):
            actions.add(ref)
            if tag != "a" or attribute != "href" or ref not in REQUIRED_ACTIONS:
                errors.append(f"unapproved direct action: {ref}")
        elif ref.startswith("https://"):
            if tag != "a" or attribute != "href" or urlparse(ref).hostname not in ALLOWED_HOSTS:
                errors.append(f"unapproved external reference: {ref}")
        elif ref.startswith(("http://", "//", "data:")):
            errors.append(f"insecure or embedded reference: {ref}")
        elif ref.startswith("#"):
            if ref[1:] not in known_ids:
                errors.append(f"missing fragment target: {ref}")
        else:
            path = (ROOT / ref.split("#", 1)[0].split("?", 1)[0]).resolve()
            try:
                path.relative_to(ROOT)
            except ValueError:
                errors.append(f"local reference escapes deployed site root: {ref}")
                continue
            if not path.exists():
                errors.append(f"missing local reference: {ref}")

    for missing in sorted(REQUIRED_ACTIONS - actions):
        errors.append(f"missing support action: {missing}")
    for index, image in enumerate(parser.images, 1):
        if "alt" not in image:
            errors.append(f"image {index} missing alt")
        if not image.get("width") or not image.get("height"):
            errors.append(f"image {index} missing intrinsic dimensions")
    for index, role in enumerate(parser.invalid_anchor_roles, 1):
        errors.append(f"link {index} overrides its native role with {role}")
    for index, button in enumerate(parser.buttons, 1):
        if button.get("type") != "button":
            errors.append(f"button {index} missing type=button")
        if "need-stop" in button.get("class", "").split():
            if button.get("aria-controls") != "need-receipt":
                errors.append(f"need button {index} has invalid aria-controls")
            if button.get("aria-pressed") not in {"true", "false"}:
                errors.append(f"need button {index} missing aria-pressed")

    required = (
        "Softer", "Start one gentle activity", "Nine activities", "Harbor Tiles", "Harbor Path",
        "No score", "No account", "no chatbot", "Need help now?",
        "Research-informed is not research-validated", "Call 988", "Call 911",
        "Repository-informed", "encrypted multi-profile", "Continue without saving",
    )
    for marker in required:
        if marker not in html:
            errors.append(f"missing product marker: {marker}")
    for marker in ("paceback", "concussion", "care plan", "model pack", "iphone", "ios app", "recovery companion"):
        if marker in public:
            errors.append(f"legacy product marker remains: {marker}")
    for marker in ("cure", "fix your mental", "clinically proven", "guaranteed to calm"):
        if marker in public:
            errors.append(f"prohibited efficacy claim remains: {marker}")
    if re.search(r"fetch\s*\(|XMLHttpRequest|WebSocket|sendBeacon", js):
        errors.append("site JavaScript may perform a network request")
    if "prefers-reduced-motion" not in css or "@media" not in css:
        errors.append("responsive/reduced-motion CSS is missing")

    return report(errors)


def report(errors):
    if errors:
        print("site checks failed:")
        for error in errors:
            print(f"- {error}")
        return 1
    print("site checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
