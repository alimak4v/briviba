# BRIVIBA SPECIFICATION v1.0

This file is the single source of truth for BRIVIBA product requirements.
If any other document conflicts with this file, this file wins.

## 1. Project Goal

Create a macOS browser focused on:

- minimal memory usage;
- minimal energy usage;
- fastest possible startup;
- modern minimalist interface;
- full isolation of third-party website state;
- no unnecessary features.

The first version supports macOS only.

BRIVIBA must use Apple native APIs only.

## 2. Technology Stack

### Language

- C++20
- Objective-C++
- Swift only for AppKit wrapper code

### UI

- AppKit
- Auto Layout
- CALayer
- CoreAnimation
- SF Symbols
- Liquid Glass

### Browser Engine

- WebKit
- WKWebView

### Build

- CMake
- Ninja
- clang

### Database

- SQLite

### Storage

- filesystem
- mmap

### Networking

- NSURLSession
- Network.framework

## 3. Non-Functional Requirements

- Application startup: less than 300 ms
- New tab startup: less than 50 ms
- Empty window RAM usage: less than 150 MB
- Idle CPU: approximately 0%
- Minimal application size
- Maximum use of system libraries

Forbidden:

- Electron
- Chromium
- Qt
- third-party UI frameworks

## 4. UI

The UI must match the reference render exactly.

It must not be merely similar.
It must not be only inspired by the render.
It must match the render.

Reference image:

- [docs/assets/BRIVIBA_UI_REFERENCE.jpeg](docs/assets/BRIVIBA_UI_REFERENCE.jpeg)

Required elements:

- left Liquid Glass dock;
- rounded window and controls;
- floating top address field;
- separate Back, Forward, and Reload buttons;
- separate right-side menu buttons;
- top toolbar background automatically adopts the current page color;
- page color is computed from the website DOM;
- no additional toolbars;
- no top tab strip;
- no side menus except the left dock.

All dimensions must scale proportionally.

Detailed UI rules live in [docs/UI.md](docs/UI.md).

## 5. Cookies And Site State

BRIVIBA has exactly two browsing modes.

### Normal

Normal mode is always used unless Secure mode is explicitly enabled.

For each top-level site, BRIVIBA creates a separate storage area.
For each embedded origin, BRIVIBA creates a separate partition.

Example:

```text
youtube.com
    google.com
    doubleclick.net
    img.youtube.com
```

Each origin has independent state.

The following state must be isolated:

- Cookies
- LocalStorage
- SessionStorage
- IndexedDB
- Cache API
- Service Workers
- HTTP Cache
- Network State
- Authentication Cache

### Secure

Secure mode works like Incognito.

After the last Secure window closes, all Secure mode data is fully deleted.
No Secure mode data may remain on disk.

## 6. Storage

All persistent state is stored on disk.

Only the current working set is loaded into RAM.

When a tab closes, tab memory must be released.

## 7. Rendering

Each tab owns its own WKWebView.

When a tab closes, its WKWebView is destroyed.

Unused tabs are unloaded.

## 8. Architecture

The required high-level architecture is:

```text
Application
    WindowManager
        BrowserWindow
            Toolbar
            Sidebar
            TabManager
                Tab
                    WKWebView
            StorageManager
            CookieManager
            HistoryManager
            BookmarkManager
            DownloadManager
            SettingsManager
```

Modules must not know each other's internals.

Modules communicate only through interfaces.

Detailed architecture rules live in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## 9. Repository Structure

The repository must use this structure:

```text
briviba/
    docs/
    src/
    include/
    resources/
    tests/
    third_party/
    CMakeLists.txt
    README.md
    LICENSE
```

## 10. Coding Style

Required:

- Google C++ style
- RAII
- no global variables
- no singletons
- no raw `new` or `delete` outside smart-pointer implementation internals
- const correctness everywhere
- `constexpr` where possible
- mandatory clang-format

Detailed coding rules live in [docs/CODING_RULES.md](docs/CODING_RULES.md).

## 11. Git Workflow

After each completed change:

```sh
git add .
git commit -m "<type>: message"
git push
```

Allowed commit types:

```text
feat
fix
perf
docs
refactor
test
build
style
```

## 12. Development Order

Codex must follow this order:

1. Create project structure.
2. Configure CMake.
3. Configure AppKit.
4. Create window.
5. Add Liquid Glass sidebar.
6. Add toolbar.
7. Add WKWebView.
8. Add URL loading.
9. Add history.
10. Add cookies.
11. Add partition storage.
12. Add Secure mode.
13. Add bookmarks.
14. Add downloads.
15. Add settings.

## 13. Rules For Codex

Forbidden:

- changing architecture without necessity;
- using third-party UI frameworks;
- rewriting working subsystems without reason;
- adding dependencies without explicit necessity;
- writing TODOs instead of implementation;
- creating stubs instead of working functionality;
- violating the existing code style.

Every new feature must:

- compile;
- preserve existing behavior;
- include a commit;
- include a short README or CHANGELOG entry if it changes application behavior.

