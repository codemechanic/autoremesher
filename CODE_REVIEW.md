# AutoRemesher — Code Review & Improvement Report

**Date:** 2026-07-09
**Branch reviewed:** `fixins`
**Scope:** Full-repo sweep (build system, CLI, CI, docs). Third-party vendored code
(`thirdparty/`, `src/tiny_obj_loader.h`) was excluded from defect review.

## How this was verified

- `qmake CONFIG+=sdk_no_version_check && make -j$(sysctl -n hw.logicalcpu)` **builds
  and links cleanly** on this Apple-Silicon Mac (Qt 5.15.19, macOS SDK 26.5, clang).
- The built CLI **remeshes correctly**: a tetrahedron → `Quads: 87, Non-quads: 7,
  Vertices: 97, Time: 0.022s`, exit code `0`, valid `.obj` written.
- `autoremesher --input <nonexistent>.obj` **hangs indefinitely** (killed after 2 min).

Conclusion: the README build commands *do* work once dependencies are installed on
Apple Silicon; the reported "commands don't work" traces to the Homebrew-path
inconsistency in **ISSUE-3** (and to missing deps).

---

## Priority order (recommended execution sequence)

| Order | Issue | Title | Priority | Effort | Status |
|-------|-------|-------|----------|--------|--------|
| 1 | ISSUE-1 | Headless mode hangs forever on load failure | P0 | S | ✅ Fixed (PR #1) |
| 2 | ISSUE-3 | macOS Homebrew paths inconsistent (README vs `.pro` vs CI) | P0 | S | ✅ Fixed (PR #1) |
| 3 | ISSUE-2 | CLI returns exit code 0 on failure | P0 | S | ✅ Fixed (PR #1) |
| 4 | ISSUE-4 | No CLI input/argument validation | P1 | M | ✅ Fixed |
| 5 | ISSUE-5 | No automated tests | P1 | M | ✅ Fixed |
| 6 | ISSUE-7 | `ci/lint.sh` breaks on paths with spaces | P2 | S | Open |
| 7 | ISSUE-6 | Duplicate `PLATFORM = "Unknown"` in `.pro` | P2 | XS | Open |
| 8 | ISSUE-8 | README build-doc nits | P2 | S | Open |
| 9 | ISSUE-11 | Unfilled `%1–%4` placeholders in compact stylesheet | P2 | S | Open |
| 10 | ISSUE-9 | Headless still requires GUI + display | P3 | L | Open |
| 11 | ISSUE-10 | Large vendored `thirdparty/` in-tree | P3 | L | Open |

**Sequencing notes:**
- Do **ISSUE-1 before ISSUE-2** — the exit-code fix is unreachable while the process
  hangs before the event loop starts.
- ISSUE-1, 2, 3 are all small and independent-ish; they form a single "make the CLI
  behave" PR.
- ISSUE-4 and ISSUE-5 pair naturally: add validation, then lock it in with tests.

---

## P0 — Correctness blockers

### ISSUE-1 — Headless mode hangs forever on any load failure
**Priority:** P0 · **Severity:** High · **Effort:** Small
**Location:** `src/mainwindow.cpp:744-757`, invoked from `src/main.cpp:213`

**Description**
`MainWindow::runHeadless()` runs **synchronously inside `main()`**, before
`app.exec()` starts the event loop. On a failed/missing input it calls
`QCoreApplication::quit()` and returns. Per Qt semantics, `quit()` is a **no-op when
the event loop is not yet running**, so control falls through to `return app.exec()`
(`src/main.cpp:215`) and the process blocks forever with nothing to quit it.

The success path avoids this only by accident: generation runs on a worker thread and
emits `headlessFinished` *during* `exec()`, where `quit()` works.

**Reproduction**
```bash
./autoremesher --input /tmp/does_not_exist.obj --output /tmp/out.obj
# prints nothing, never exits — hangs until killed
```

**Recommended fix**
Defer the headless kickoff into the event loop so early failures can quit cleanly:
```cpp
// src/main.cpp — instead of calling runHeadless() directly:
QTimer::singleShot(0, mainWindow, &MainWindow::runHeadless);
return app.exec();
```
or make the failure paths event-loop-safe:
```cpp
QMetaObject::invokeMethod(qApp, "quit", Qt::QueuedConnection);
```

---

### ISSUE-2 — CLI returns exit code 0 on failure
**Priority:** P0 · **Severity:** High · **Effort:** Small
**Location:** `src/mainwindow.cpp:753-756`, `881-883`; `src/main.cpp:206`

**Description**
Every headless termination path exits with status `0`:
- load failure → `QCoreApplication::quit()` (status 0),
- "Remeshing produced no result" → `headlessFinished(0,0,0,…)` then `quit()` (status 0),
- success → `QCoreApplication::quit()` (status 0).

A caller (CI, batch script, pipeline) cannot distinguish success from failure. The CI
smoke tests currently rely on checking whether the output file exists as a proxy.

**Recommended fix**
Use `QCoreApplication::exit(1)` on error paths (and keep `exit(0)`/`quit()` on
success). Depends on ISSUE-1 (the error path must be reachable inside the loop).

---

### ISSUE-3 — macOS Homebrew paths are inconsistent (README vs `.pro` vs CI)
**Priority:** P0 · **Severity:** High (portability) · **Effort:** Small
**Location:** `README.md:77`; `autoremesher.pro:455-458`; `.github/workflows/release.yml:426,432`

**Description**
The project mixes Intel and Apple-Silicon Homebrew prefixes:
- `README.md` and CI export the **Intel** path: `export PATH="/usr/local/opt/qt@5/bin:$PATH"`.
- `autoremesher.pro` hardcodes the **Apple-Silicon** TBB path:
  `INCLUDEPATH += /opt/homebrew/opt/tbb/include` and `-L/opt/homebrew/opt/tbb/lib`.

Consequences:
- **Intel Mac:** the `.pro` TBB path (`/opt/homebrew/...`) does not exist → link failure.
- **Apple-Silicon Mac:** the README `PATH` export points at a nonexistent dir; the build
  only succeeds because `/opt/homebrew/bin` is already on `PATH` from `brew shellenv`.
- **CI:** `macos-latest` runners are now arm64, so the `/usr/local/...` export in
  `release.yml` is effectively dead (works only via the default `PATH`).

This is the most likely explanation for "the README commands don't work."

**Recommended fix**
Make the `.pro` architecture-agnostic and update the docs/CI to match:
```qmake
# autoremesher.pro (macx block)
TBB_PREFIX = $$system(brew --prefix tbb)
INCLUDEPATH += $$TBB_PREFIX/include
LIBS += -L$$TBB_PREFIX/lib -ltbbmalloc_proxy -ltbbmalloc -ltbb
```
```bash
# README.md and release.yml
export PATH="$(brew --prefix qt@5)/bin:$PATH"
```

---

## P1 — Robustness

### ISSUE-4 — No CLI input/argument validation
**Priority:** P1 · **Severity:** Medium · **Effort:** Medium
**Location:** `src/main.cpp:54-72`

**Description**
Numeric options are parsed with `QString::toInt()` / `toDouble()`, which **return 0 on
parse failure** with no error. `--target-quads abc` silently becomes `0`. There is no
existence check on `--input`, and the documented ranges (e.g. `adaptivity 0.0-1.0`,
`edge-scaling 1.0-4.0`) are not enforced.

**Recommended fix**
Use the `bool* ok` overloads, validate ranges, and fail fast:
```cpp
bool ok = false;
params.targetQuads = parser.value("target-quads").toInt(&ok);
if (!ok || params.targetQuads <= 0) { std::cerr << "Invalid --target-quads\n"; return 1; }
```
Check `QFileInfo::exists()` on the input before entering the event loop.

---

### ISSUE-5 — No automated tests
**Priority:** P1 · **Severity:** Medium · **Effort:** Medium
**Location:** repo-wide (no `test/` directory)

**Description**
The only regression coverage is a single armadillo CLI smoke test per platform in
`release.yml`. There are no unit or golden-file tests for the remesh core, so
algorithmic regressions in `quadextractor.cpp` / `parameterizer.cpp` (the largest,
most complex files) can ship undetected.

**Recommended fix**
Add a small `test/` suite driven from CI: a handful of tiny input meshes remeshed via
the CLI with assertions on quad/vertex counts within tolerance, plus a couple of
degenerate inputs (empty mesh, single triangle, non-manifold) to guard the error paths
fixed in ISSUE-1/2/4.

---

## P2 — Build / CI / docs quality

### ISSUE-6 — Duplicate `PLATFORM = "Unknown"` in `.pro`
**Priority:** P2 · **Severity:** Low · **Effort:** Trivial
**Location:** `autoremesher.pro:45` and `:47`

`PLATFORM = "Unknown"` is assigned twice in a row. Remove the redundant line.

---

### ISSUE-7 — `ci/lint.sh` breaks on paths with spaces / fragile `find`
**Priority:** P2 · **Severity:** Low · **Effort:** Small
**Location:** `ci/lint.sh:6`

**Description**
```sh
find "$PROJECT_DIR/src" -iname "*.h" -o -iname "*.cpp" | xargs clang-format -style=file -i
```
The `-o` is ungrouped (relies on `find`'s default-action precedence), and `xargs`
without `-0` splits on whitespace, so any path containing spaces is mishandled.

**Recommended fix**
```sh
find "$PROJECT_DIR/src" \( -name '*.h' -o -name '*.cpp' \) -print0 \
  | xargs -0 clang-format -style=file -i
```

---

### ISSUE-8 — README build-doc nits
**Priority:** P2 · **Severity:** Low · **Effort:** Small
**Location:** `README.md:31-36, 67-82`

- The Prerequisites imply you already have the repo, yet each platform block repeats
  `git clone … && cd autoremesher`.
- The macOS block gives no guidance on Apple-Silicon vs Intel Homebrew prefixes
  (see ISSUE-3).
- Consider a one-line "if `qmake` is not found, ensure `$(brew --prefix qt@5)/bin` is
  on `PATH`" troubleshooting note — this is the exact symptom users report.

---

## P3 — Nice-to-have / larger efforts

### ISSUE-9 — Headless mode still requires a full GUI + display
**Priority:** P3 · **Severity:** Low · **Effort:** Large
**Location:** `src/main.cpp:76, 133-160`

**Description**
Even in `--input` (CLI) mode, `main()` constructs a `QApplication`, a full dark
`QPalette`, fonts, and a 3.3 Core OpenGL surface. This is why CI must run under Xvfb
(Linux) / `QT_QPA_PLATFORM=offscreen` (Windows) and cannot run on a truly headless
server. `QApplication::setOverrideCursor(Qt::WaitCursor)` in `runHeadless()` is also a
no-op without a GUI.

**Recommended fix (larger)**
Split a genuine headless path that uses `QCoreApplication`/`QGuiApplication`, skips
theming, and drives the remesh pipeline directly without the render widgets.

---

### ISSUE-10 — Large vendored `thirdparty/` committed in-tree
**Priority:** P3 · **Severity:** Low (maintainability) · **Effort:** Large
**Location:** `thirdparty/` (geogram 1.8.3, eigen, tbb, QtAwesome, …)

**Description**
Dependencies are vendored as full source copies with no submodule/pin metadata, making
provenance and security updates hard to track.

**Recommended fix**
Move to git submodules or a documented vendoring script that records upstream
version/commit for each dependency.

---

### ISSUE-11 — Unfilled `%1–%4` placeholders in compact stylesheet
**Priority:** P2 · **Severity:** Low · **Effort:** Small
**Location:** `src/theme.cpp` (`Theme::compactStylesheet()`)

**Description**
Running the CLI prints `QString::arg: 1 argument(s) missing` and dumps the raw
stylesheet, because the stylesheet string contains `%1`–`%4` placeholders that are
never substituted via `QString::arg(...)`. Cosmetic (stderr noise) but pollutes CLI
output and indicates the themed colors aren't actually applied. Found while verifying
the ISSUE-1 fix.

**Recommended fix**
Chain `.arg(...)` calls for each placeholder (or hardcode the resolved colors).

---

## Appendix — items intentionally *not* flagged as defects

- `-flto -funroll-loops -O3` on macOS and `-DNL_USE_BLAS` + `-framework Accelerate`
  (recent commit `dac477b1`) build and link fine here.
- `main()` building GUI resources in headless mode is wasteful but harmless (folded
  into ISSUE-9).
- `TODO/FIXME` markers under `src/tiny_obj_loader.h` and `thirdparty/` are upstream and
  out of scope.
