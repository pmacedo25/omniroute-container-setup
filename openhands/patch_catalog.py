"""Patch the pinned OpenHands UI for OmniRoute and PWA installation."""

import json
from pathlib import Path


assets = Path("/app/frontend/build/assets")
matches = list(assets.glob("model-selector-*.js"))
if len(matches) != 1:
    raise RuntimeError(f"Expected one model-selector asset, found {len(matches)}")

path = matches[0]
source = path.read_text(encoding="utf-8")

parser_old = 'const k=s=>{const[t,...r]=s.split("/");'
parser_new = (
    'const k=s=>{if(s.startsWith("openai/combo-"))'
    'return{provider:"omniroute",model:s,separator:"/"};'
    'const[t,...r]=s.split("/");'
)
selection_old = 'd==="openai"&&(f=e)'
selection_new = '(d==="openai"||d==="omniroute")&&(f=e)'

if parser_old not in source or selection_old not in source:
    raise RuntimeError("Pinned OpenHands model selector contract changed")

source = source.replace(parser_old, parser_new, 1)
source = source.replace(selection_old, selection_new, 1)
path.write_text(source, encoding="utf-8")

frontend_build = Path("/app/frontend/build")
manifest_path = frontend_build / "manifest.webmanifest"
manifest_path.write_text(
    json.dumps(
        {
            "id": "/",
            "name": "OpenHands",
            "short_name": "OpenHands",
            "description": "OpenHands via OmniRoute",
            "start_url": "/",
            "scope": "/",
            "display": "standalone",
            "background_color": "#0d0f10",
            "theme_color": "#0d0f10",
            "icons": [
                {
                    "src": "/favicon.ico",
                    "sizes": "any",
                    "type": "image/x-icon",
                    "purpose": "any",
                }
            ],
        },
        indent=2,
    ),
    encoding="utf-8",
)

index_path = frontend_build / "index.html"
index_html = index_path.read_text(encoding="utf-8")
if 'rel="manifest"' not in index_html:
    index_html = index_html.replace(
        "</head>",
        '<link rel="manifest" href="/manifest.webmanifest">'
        '<meta name="theme-color" content="#0d0f10"></head>',
    )
    index_path.write_text(index_html, encoding="utf-8")
