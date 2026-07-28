# BRIVIBA Coding Rules

Product requirements are defined in [../SPEC.md](../SPEC.md).

## 1. General Rules

Required:

- simple native macOS implementation;
- minimal dependencies;
- clear ownership;
- small modules;
- predictable interfaces;
- compile after each completed change.

Forbidden:

- Electron;
- Chromium;
- Qt;
- third-party UI frameworks;
- unnecessary dependencies;
- global variables;
- singletons;
- raw `new` and `delete` outside smart-pointer implementation internals;
- TODO comments instead of implementation;
- stubs presented as complete functionality.

## 2. C++ Style

Required:

- C++20;
- Google C++ style;
- RAII;
- const correctness;
- `constexpr` where useful;
- smart pointers for ownership;
- references or raw pointers only for non-owning relationships when lifetime is clear.

## 3. Objective-C++ Style

Required:

- Objective-C++ only where C++ and AppKit/WebKit must meet;
- keep `.mm` files narrow;
- expose C++ interfaces where practical;
- do not leak AppKit details into pure C++ modules.

## 4. Swift Style

Swift is allowed only for AppKit wrapper code.

Swift must not become the main application logic layer unless the specification is updated.

## 5. Formatting

Required:

- clang-format for C++ and Objective-C++;
- consistent file naming;
- no unrelated formatting churn;
- no mass rewrites unless required by the current change.

## 6. Dependencies

Allowed by default:

- Apple system frameworks;
- WebKit;
- SQLite;
- CMake;
- Ninja.

Any other dependency requires explicit justification and must be added only when native APIs are insufficient.

## 7. Testing And Verification

Every completed implementation step must be verified.

Minimum checks:

- project config step: configure with CMake;
- build step: compile successfully;
- UI step: run and visually inspect screenshot;
- WebKit step: load a real URL or local test page;
- storage step: verify data is written to the expected partition;
- Secure mode step: verify data is deleted after the last Secure window closes.

## 8. Documentation Updates

Update README or CHANGELOG when behavior changes.

Documentation-only changes do not require README or CHANGELOG updates unless they change project instructions.

## 9. Git Workflow

After each finished change:

```sh
git add .
git commit -m "<type>: message"
git push
```

Allowed types:

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

