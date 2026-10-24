#!/usr/bin/env python3
"""Serves web/ for local use: python3 web/serve.py [port]  ->  http://127.0.0.1:8080

A static server is all the PWA needs — there is no backend. This one exists because the two
types the app depends on are missing from older Pythons' tables: .mjs must be JavaScript or the
browser refuses the module, and .wasm must be application/wasm or the engine will not stream in.

To reach it from a phone on the same network, bind 0.0.0.0 and use the Mac's address. Browsers
only install a PWA over https or from localhost, so an install prompt on the phone needs a
tunnel (Tailscale, ngrok) or a certificate; reading works either way.
"""
import functools
import http.server
import sys
from pathlib import Path


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".mjs": "text/javascript",
        ".js": "text/javascript",
        ".wasm": "application/wasm",
        ".webmanifest": "application/manifest+json",
    }

    def end_headers(self):
        # A service worker caches aggressively; during development the files themselves should not.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        if "304" not in fmt % args:
            super().log_message(fmt, *args)


port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
handler = functools.partial(Handler, directory=str(Path(__file__).parent))
print(f"GranthFlow on http://127.0.0.1:{port}  (ctrl-c to stop)")
http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
