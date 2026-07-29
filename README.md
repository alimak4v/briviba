# BRIVIBA

BRIVIBA is a macOS-only browser focused on low memory usage, low energy usage, fast startup, a minimal native interface, and strict site-state isolation.

The source of truth for requirements is [SPEC.md](SPEC.md).

Supporting documents:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/UI.md](docs/UI.md)
- [docs/CODING_RULES.md](docs/CODING_RULES.md)

## Current Implementation

Briviba currently builds as a native macOS AppKit/WebKit app bundle with:

- native window, Liquid Glass sidebar, floating toolbar, and WKWebView content area;
- URL loading, Back, Forward, Reload, page-derived chrome color, and basic tabs;
- visible sidebar tab indicators with tab switching;
- SQLite-backed history, bookmarks, downloads, settings, and site-container mapping;
- Normal mode per-top-level-site WebKit data stores;
- Secure mode using non-persistent WebKit storage;
- Safari-like WebKit user agent;
- inactive tab WKWebView unloading.
