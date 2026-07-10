# Third-party dependencies

AutoRemesher vendors its third-party dependencies directly in this `thirdparty/`
directory (they are committed to the repo, not fetched at build time). This file is
the **provenance manifest**: it records where each dependency came from, its version,
its license, and any local modifications, so that security/version audits and future
updates have a single source of truth.

## Why vendored (and not git submodules)

Some dependencies — geogram in particular — carry **local patches** that the build and
runtime depend on (see [Local modifications](#local-modifications) below). Replacing the
vendored copies with pristine upstream submodules would silently drop those patches and
regress the build. The dependencies are therefore kept in-tree; this manifest exists to
give them the provenance a submodule pin normally would.

## Inventory

| Dependency | Version | License | Upstream | Local mods |
|------------|---------|---------|----------|-----------|
| **geogram** | 1.8.3 | BSD-3-Clause | https://github.com/BrunoLevy/geogram | **Yes** — see below |
| **eigen** | 3.3.7 | MPL-2.0 (core) | https://gitlab.com/libeigen/eigen | No (as imported) |
| **tbb** (Intel TBB) | 2017 (interface 9100) | Apache-2.0 | https://github.com/oneapi-src/oneTBB | No (as imported) |
| **QtAwesome** | as imported | MIT | https://github.com/gamecreature/QtAwesome | No |
| **QtWaitingSpinner** | as imported | MIT | https://github.com/snowwlex/QtWaitingSpinner | Minor (relicense/layout) |
| **isotropicremesher** | as imported | MIT | https://github.com/huxingyi/isotropicremesher | Companion project (same author) |

Versions were read from source (`Eigen/src/Core/util/Macros.h`, geogram
`CMakeLists.txt`, `tbb/include/tbb/tbb_stddef.h`). Exact upstream commit SHAs were not
recorded when these were originally vendored — **record the pinned tag/commit in this
table whenever a dependency is next updated** (see [Updating](#updating-a-dependency)).

## Local modifications

Only **geogram 1.8.3** carries functional local patches. These must be preserved across
any future re-vendoring:

| File | Change | Commit |
|------|--------|--------|
| `geogram/geogram-1.8.3/src/lib/geogram/NL/nl_blas.c` | Use the platform BLAS (Accelerate on macOS, `NL_USE_BLAS`) | `dac477b1` |
| `geogram/geogram-1.8.3/src/lib/geogram/NL/nl_linkage.h` | Build fix | `b61363da` |
| `geogram/geogram-1.8.3/src/lib/exploragram/hexdom/quad_cover.cpp` | Replace `geo_assert` crashes in wheel-compatibility constraints with a graceful singular-vertex fallback | `808ecc23` |
| `geogram/geogram_report_progress.h` | Project-added shim header for parameterization progress reporting | `979e630c` |

Additionally, the OpenNL sources are built through the project's own
`src/AutoRemesher/nl_ext_stubs.c` and the `NL_USE_BLAS` define (set in
`autoremesher.pro`) rather than geogram's stock configuration.

> Historical note: earlier revisions vendored geogram **1.7.5** with OpenNL
> multi-threading patches (`ce05e100`, `8d8bb2fd`). That copy was replaced wholesale by
> 1.8.3 in the MIT relicense (`533c6bad`) and no longer exists in the tree.

## Updating a dependency

1. Fetch the target upstream release; note its **tag and commit SHA**.
2. Replace the vendored files.
3. **Re-apply every patch** listed under [Local modifications](#local-modifications) for
   that dependency (diff the commits above against the new upstream to port them).
4. Update the source file list in `autoremesher.pro` if upstream added/removed files.
5. Update this manifest: bump the version, fill in the pinned commit SHA, and adjust the
   modifications table.
6. Rebuild and run the tests: `./test/run_tests.sh`.

## Security auditing

The inventory table is the starting point for CVE/version checks. Note the older pins
(Intel TBB 2017, Eigen 3.3.7) when assessing advisories; upgrading them is tracked as
future maintenance work.
