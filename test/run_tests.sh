#!/usr/bin/env bash
#
# CLI behavior tests for AutoRemesher.
#
# These are black-box tests that drive the built binary the same way a user or
# CI pipeline would. They guard the headless entry point: exit codes, argument
# validation, and that a valid input actually produces a quad mesh.
#
# Usage:
#   test/run_tests.sh [path-to-binary]
#
# The binary is resolved in this order:
#   1. the first CLI argument
#   2. the $AUTOREMESHER_BIN environment variable
#   3. common build output locations (Linux ./autoremesher, macOS .app, Windows)
#
# In headless (--input) mode the tool auto-selects Qt's offscreen platform, so
# no display / X server / xvfb is required — this runs anywhere.
#
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- Locate the binary -------------------------------------------------------
BIN="${1:-${AUTOREMESHER_BIN:-}}"
if [ -z "$BIN" ]; then
    for candidate in \
        "$SCRIPT_DIR/../autoremesher" \
        "$SCRIPT_DIR/../autoremesher.app/Contents/MacOS/autoremesher" \
        "$SCRIPT_DIR/../release/autoremesher.exe"; do
        if [ -x "$candidate" ]; then BIN="$candidate"; break; fi
    done
fi
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
    echo "ERROR: could not find the autoremesher binary. Pass it as the first argument."
    exit 2
fi
echo "Testing binary: $BIN"

# --- Portable per-test timeout ----------------------------------------------
# `timeout` is absent on stock macOS; fall back to a perl alarm wrapper.
run_bounded() { # run_bounded <seconds> <cmd...>
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$secs" "$@"
    else
        perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
    fi
}

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Assert the binary exits with an expected status for the given args.
# expect_exit <name> <expected_status> <args...>
expect_exit() {
    local name="$1"; local expected="$2"; shift 2
    run_bounded 120 "$BIN" "$@" >"$WORK/out.log" 2>&1
    local status=$?
    if [ "$status" -eq "$expected" ]; then
        pass "$name (exit $status)"
    else
        fail "$name (expected exit $expected, got $status)"
        sed 's/^/    | /' "$WORK/out.log" | tail -5
    fi
}

echo
echo "== Argument validation (must reject and exit 1) =="
expect_exit "missing input file"        1 --input "$WORK/nope.obj" --output "$WORK/o.obj"
expect_exit "missing --output"          1 --input "$FIXTURES/tetra.obj"
expect_exit "non-numeric target-quads"  1 --input "$FIXTURES/tetra.obj" --output "$WORK/o.obj" --target-quads abc
expect_exit "zero target-quads"         1 --input "$FIXTURES/tetra.obj" --output "$WORK/o.obj" --target-quads 0
expect_exit "adaptivity out of range"   1 --input "$FIXTURES/tetra.obj" --output "$WORK/o.obj" --adaptivity 2.0
expect_exit "edge-scaling out of range" 1 --input "$FIXTURES/tetra.obj" --output "$WORK/o.obj" --edge-scaling 0.5
expect_exit "sharp-edge out of range"   1 --input "$FIXTURES/tetra.obj" --output "$WORK/o.obj" --sharp-edge 10

echo
echo "== Malformed / unusable input and output (must reject, not crash or hang) =="
expect_exit "out-of-range vertex index" 1 --input "$FIXTURES/bad_index.obj" --output "$WORK/o.obj"
expect_exit "empty (no geometry) input" 1 --input "$FIXTURES/empty.obj" --output "$WORK/o.obj"
expect_exit "unwritable output path"    1 --input "$FIXTURES/tetra.obj" --output "$WORK/no_such_dir/o.obj" --target-quads 200

echo
echo "== Valid remesh (must succeed, exit 0, and produce a quad mesh) =="
for fixture in tetra octahedron; do
    out="$WORK/${fixture}_out.obj"
    report="$WORK/${fixture}_report.txt"
    run_bounded 180 "$BIN" \
        --input "$FIXTURES/${fixture}.obj" \
        --output "$out" \
        --report "$report" \
        --target-quads 200 >"$WORK/run.log" 2>&1
    status=$?
    if [ "$status" -ne 0 ]; then
        fail "remesh $fixture (exit $status)"
        sed 's/^/    | /' "$WORK/run.log" | tail -8
        continue
    fi
    if [ ! -s "$out" ]; then
        fail "remesh $fixture (output file missing or empty)"
        continue
    fi
    verts=$(grep -c '^v ' "$out")
    faces=$(grep -c '^f ' "$out")
    quads=0
    if [ -f "$report" ]; then
        quads=$(grep -oE 'Quads: *[0-9]+' "$report" | grep -oE '[0-9]+' | head -1)
        quads=${quads:-0}
    fi
    # Loose tolerance: exact counts vary by platform/version, so only assert the
    # remesh produced a non-trivial quad-dominant mesh.
    if [ "$verts" -gt 3 ] && [ "$faces" -gt 0 ] && [ "$quads" -gt 0 ]; then
        pass "remesh $fixture (verts=$verts faces=$faces quads=$quads)"
    else
        fail "remesh $fixture (verts=$verts faces=$faces quads=$quads)"
    fi
done

echo
echo "== Summary: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
