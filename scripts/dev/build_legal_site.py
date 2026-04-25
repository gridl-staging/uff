#!/usr/bin/env python3
"""Render the repo's legal markdown docs into a minimal static HTML site.

Output layout under ``tmp/legal_site/``:

- ``index.html`` - landing page with links to privacy + terms
- ``privacy/index.html`` - rendered privacy policy (served at ``/privacy``)
- ``terms/index.html`` - rendered terms of service (served at ``/terms``)

The site is designed to be deployed to Cloudflare Pages via
``scripts/dev/deploy_legal_site.sh``. The source of truth for the legal text
stays in ``docs/privacy_policy.md`` and ``docs/terms_of_service.md``; this
script does not edit those files, only renders them.
"""

from __future__ import annotations

import html as html_lib
import sys
from pathlib import Path

import markdown

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DOCS_DIR = REPO_ROOT / "docs"
OUTPUT_DIR = REPO_ROOT / "tmp" / "legal_site"

PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<meta name="robots" content="index,follow">
<style>
:root {{
  color-scheme: light dark;
  --fg: #1a1a1a;
  --bg: #ffffff;
  --muted: #555555;
  --link: #0050c8;
  --border: #e0e0e0;
}}
@media (prefers-color-scheme: dark) {{
  :root {{
    --fg: #e8e8e8;
    --bg: #121212;
    --muted: #a0a0a0;
    --link: #6ea8ff;
    --border: #2a2a2a;
  }}
}}
* {{ box-sizing: border-box; }}
body {{
  margin: 0 auto;
  max-width: 760px;
  padding: 2rem 1.25rem 4rem;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  font-size: 17px;
  line-height: 1.6;
  color: var(--fg);
  background: var(--bg);
}}
header {{
  border-bottom: 1px solid var(--border);
  margin-bottom: 2rem;
  padding-bottom: 1rem;
  font-size: 0.9rem;
  color: var(--muted);
}}
header a {{ color: var(--muted); text-decoration: none; margin-right: 1rem; }}
header a:hover {{ color: var(--link); }}
h1 {{ font-size: 1.9rem; margin: 0 0 0.5rem; }}
h2 {{ font-size: 1.35rem; margin: 2rem 0 0.75rem; }}
h3 {{ font-size: 1.1rem; margin: 1.5rem 0 0.5rem; }}
p, li {{ margin: 0.5rem 0; }}
ul, ol {{ padding-left: 1.5rem; }}
a {{ color: var(--link); }}
hr {{ border: 0; border-top: 1px solid var(--border); margin: 2rem 0; }}
footer {{
  margin-top: 3rem;
  padding-top: 1rem;
  border-top: 1px solid var(--border);
  color: var(--muted);
  font-size: 0.85rem;
}}
</style>
</head>
<body>
<header>
<a href="/">Home</a>
<a href="/privacy">Privacy</a>
<a href="/terms">Terms</a>
</header>
<main>
{body}
</main>
<footer>
Questions or data requests: <a href="mailto:hi@uff.app">hi@uff.app</a>.
Third Fork Labs LLC, 4030 Wake Forest Road, Ste 349, Raleigh, NC 27609, USA.
</footer>
</body>
</html>
"""

INDEX_BODY = """<h1>Uff Legal</h1>
<p>The Uff running app is operated by Third Fork Labs LLC. These pages are the
current versions of the app's public legal documents.</p>
<ul>
<li><a href="/privacy">Privacy Policy</a></li>
<li><a href="/terms">Terms of Service</a></li>
</ul>
<p>For privacy questions or data requests, contact
<a href="mailto:hi@uff.app">hi@uff.app</a>.</p>
"""


def render_markdown_to_page(
    source_path: Path,
    output_path: Path,
    title: str,
    description: str,
) -> None:
    """Convert a markdown file to an HTML page in the PAGE_TEMPLATE."""
    source_text = source_path.read_text(encoding="utf-8")
    # Strip the first H1 since the template doesn't use it separately; the
    # markdown H1 becomes the in-page title, which is what we want.
    body_html = markdown.markdown(
        source_text,
        extensions=["extra", "sane_lists"],
    )
    page = PAGE_TEMPLATE.format(
        title=html_lib.escape(title),
        description=html_lib.escape(description),
        body=body_html,
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(page, encoding="utf-8")


def main() -> int:
    if not DOCS_DIR.is_dir():
        print(f"ERROR: docs dir missing at {DOCS_DIR}", file=sys.stderr)
        return 1

    privacy_src = DOCS_DIR / "privacy_policy.md"
    terms_src = DOCS_DIR / "terms_of_service.md"
    for src in (privacy_src, terms_src):
        if not src.is_file():
            print(f"ERROR: required source missing: {src}", file=sys.stderr)
            return 1

    if OUTPUT_DIR.exists():
        # Clean previous build so stale files do not ship.
        for path in sorted(OUTPUT_DIR.rglob("*"), reverse=True):
            if path.is_file():
                path.unlink()
            elif path.is_dir():
                path.rmdir()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Landing page.
    (OUTPUT_DIR / "index.html").write_text(
        PAGE_TEMPLATE.format(
            title="Uff Legal",
            description=(
                "Public legal documents for the Uff running app, operated by "
                "Third Fork Labs LLC."
            ),
            body=INDEX_BODY,
        ),
        encoding="utf-8",
    )

    render_markdown_to_page(
        source_path=privacy_src,
        output_path=OUTPUT_DIR / "privacy" / "index.html",
        title="Uff Privacy Policy",
        description=(
            "Uff mobile app privacy policy, operated by Third Fork Labs LLC."
        ),
    )

    render_markdown_to_page(
        source_path=terms_src,
        output_path=OUTPUT_DIR / "terms" / "index.html",
        title="Uff Terms of Service",
        description=(
            "Uff mobile app terms of service, operated by Third Fork Labs LLC."
        ),
    )

    pages = [
        OUTPUT_DIR / "index.html",
        OUTPUT_DIR / "privacy" / "index.html",
        OUTPUT_DIR / "terms" / "index.html",
    ]
    for page in pages:
        size = page.stat().st_size
        rel = page.relative_to(REPO_ROOT)
        print(f"wrote {rel} ({size:,} bytes)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
