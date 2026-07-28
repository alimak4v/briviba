# BRIVIBA Architecture

This document defines module boundaries and ownership.
Product requirements are defined in [../SPEC.md](../SPEC.md).

## 1. Required Module Tree

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

## 2. Boundary Rules

- Modules must communicate through explicit interfaces.
- A module must not depend on another module's private implementation details.
- Ownership must be visible in type signatures.
- Long-lived ownership must use RAII.
- UI modules must not own persistence policy.
- Persistence modules must not own AppKit views.
- WebKit integration must be isolated behind browser-facing interfaces.

## 3. Application

Responsibilities:

- process lifetime;
- application delegate setup;
- dependency construction;
- top-level shutdown.

The application layer must not contain browser feature logic.

## 4. WindowManager

Responsibilities:

- creating browser windows;
- tracking open windows;
- coordinating normal shutdown;
- detecting when the last Secure window closes.

WindowManager owns BrowserWindow instances.

## 5. BrowserWindow

Responsibilities:

- native NSWindow lifecycle;
- connecting Toolbar, Sidebar, and TabManager;
- routing user commands to the correct module;
- window-level mode state.

BrowserWindow must not directly manipulate cookies, history, bookmarks, downloads, or settings storage.

## 6. Toolbar

Responsibilities:

- Back, Forward, Reload controls;
- floating address field;
- right-side menu controls;
- page-derived color presentation.

Toolbar emits commands.
It does not perform navigation itself.

## 7. Sidebar

Responsibilities:

- left Liquid Glass dock;
- primary navigation actions;
- compact visual state.

Sidebar must remain the only side menu in the application.

## 8. TabManager

Responsibilities:

- creating tabs;
- selecting active tab;
- closing tabs;
- unloading unused tabs;
- destroying closed tab WKWebView instances.

TabManager owns Tab instances.

## 9. Tab

Responsibilities:

- one WKWebView instance;
- current page state;
- navigation state;
- active page metadata.

Each Tab owns exactly one WKWebView while loaded.
When unloaded, the Tab must release the WKWebView.

## 10. StorageManager

Responsibilities:

- filesystem layout;
- mmap-backed data access where useful;
- lifecycle of persistent storage;
- cleanup of Secure mode storage.

StorageManager owns storage location decisions.

## 11. CookieManager

Responsibilities:

- top-level site isolation;
- embedded origin partitioning;
- Secure mode ephemeral state;
- cookie and website data cleanup.

CookieManager must isolate all state listed in [../SPEC.md](../SPEC.md#5-cookies-and-site-state).

## 12. HistoryManager

Responsibilities:

- visited URL records;
- visit timestamps;
- title and favicon metadata where available;
- history queries.

HistoryManager must not own navigation.

## 13. BookmarkManager

Responsibilities:

- bookmarks;
- bookmark folders if introduced;
- bookmark persistence.

BookmarkManager must not own history.

## 14. DownloadManager

Responsibilities:

- download lifecycle;
- destination selection;
- progress;
- cancellation;
- completion state.

DownloadManager must use native Apple networking or WebKit download APIs.

## 15. SettingsManager

Responsibilities:

- user settings;
- defaults;
- persistence;
- validation.

SettingsManager must not become a global singleton.

