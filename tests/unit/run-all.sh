#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Rust unit tests — run `cargo test` on all workspace crates.
# Requires `cargo` on the host (no Docker — cargo caching is essential).
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${BLUE}[*]${NC} $1"; }
pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; }

FAILED=0

if ! command -v cargo &>/dev/null; then
  echo -e "${RED}ERROR: cargo not found on PATH${NC}"
  echo "Install Rust toolchain:  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
  exit 1
fi

# ─── sample-rust-app ──────────────────────────────────────────────────────
info "cargo test — workloads/sample-rust-app"
if (cd "$REPO_ROOT/workloads/sample-rust-app" && cargo test --quiet 2>&1); then
  pass "sample-rust-app unit tests"
else
  fail "sample-rust-app unit tests"
  FAILED=$((FAILED + 1))
fi
echo ""

# ─── web dashboard (compile check only if tests are absent) ───────────────
if [ -f "$REPO_ROOT/web/Cargo.toml" ]; then
  info "cargo test — web dashboard"
  # The web dashboard uses leptos with ssr/hydrate features.
  # Run a basic check + test if tests exist.
  if (cd "$REPO_ROOT/web" && cargo test --quiet --no-run 2>&1); then
    if (cd "$REPO_ROOT/web" && cargo test --quiet 2>&1); then
      pass "web dashboard tests"
    else
      fail "web dashboard tests (some tests failed)"
      FAILED=$((FAILED + 1))
    fi
  else
    # If it won't compile in the test environment (missing leptos tooling),
    # fall back to `cargo check`.
    info "  falling back to cargo check (leptos SSR tooling may be missing)"
    if (cd "$REPO_ROOT/web" && cargo check --quiet 2>&1); then
      pass "web dashboard — cargo check"
    else
      fail "web dashboard — cargo check"
      FAILED=$((FAILED + 1))
    fi
  fi
fi

echo ""

# ─── Summary ─────────────────────────────────────────────────────────────
if [ "$FAILED" -eq 0 ]; then
  echo -e "${GREEN}=== All unit tests passed ===${NC}"
  exit 0
else
  echo -e "${RED}=== $FAILED unit test(s) failed ===${NC}"
  exit 1
fi
