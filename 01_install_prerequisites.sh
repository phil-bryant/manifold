#!/bin/bash
umask 007

#R001: Run with bash in strict fail-fast mode.
set -euo pipefail

MIN_GO_VERSION="${MANIFOLD_MIN_GO_VERSION:-1.22}"

print_header() {
    echo "============================================================"
    echo "Manifold Prerequisites Installer"
    echo "============================================================"
    echo ""
}

ensure_homebrew() {
    #R005: Verify Homebrew exists before package actions.
    echo "[Homebrew] Checking..."
    if command -v brew >/dev/null 2>&1; then
        echo "✅ [Homebrew] Installed"
    else
        echo "❌ [Homebrew] Not installed."
        echo "Install Homebrew and rerun:"
        echo "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
}

ensure_brew_formula() {
    local formula="$1" command_name="${2:-$formula}"
    echo "[${formula}] Checking..."
    if command -v "$command_name" >/dev/null 2>&1; then
        echo "✅ [${formula}] Available on PATH"
        return
    fi
    echo "⚠️  [${formula}] Missing; installing with Homebrew..."
    brew install "$formula"
    if command -v "$command_name" >/dev/null 2>&1; then
        echo "✅ [${formula}] Installed and available"
    else
        echo "❌ [${formula}] Install completed but command is still missing"
        exit 1
    fi
}

ensure_go() {
    #R010: Ensure Go toolchain is installed and available.
    ensure_brew_formula "go" "go"
}

version_is_at_least() {
    local have="$1" want="$2"
    local have_major have_minor want_major want_minor result=1
    have_major="${have%%.*}"
    have_minor="${have#*.}"
    have_minor="${have_minor%%.*}"
    want_major="${want%%.*}"
    want_minor="${want#*.}"
    want_minor="${want_minor%%.*}"
    if [ "$have_major" -gt "$want_major" ]; then
        result=0
    elif [ "$have_major" -eq "$want_major" ] && [ "$have_minor" -ge "$want_minor" ]; then
        result=0
    fi
    return "$result"
}

ensure_go_version() {
    #R015: Enforce minimum supported Go version.
    local go_version_raw go_version
    echo "[Go Version] Checking..."
    go_version_raw="$(go version | awk '{print $3}')"
    go_version="${go_version_raw#go}"
    if version_is_at_least "$go_version" "$MIN_GO_VERSION"; then
        echo "✅ [Go Version] ${go_version} (minimum ${MIN_GO_VERSION})"
        return
    fi
    echo "❌ [Go Version] ${go_version} is below required ${MIN_GO_VERSION}"
    exit 1
}

ensure_postgres_cli() {
    #R020: Ensure Postgres CLI tooling is available.
    local libpq_prefix=""
    echo "[Postgres CLI] Checking..."
    if command -v psql >/dev/null 2>&1; then
        echo "✅ [Postgres CLI] psql available on PATH"
        return
    fi
    if libpq_prefix="$(brew --prefix libpq)"; then
        if [ -n "$libpq_prefix" ] && [ -x "${libpq_prefix}/bin/psql" ]; then
            echo "✅ [Postgres CLI] Using existing fallback ${libpq_prefix}/bin/psql"
            return
        fi
    fi
    echo "⚠️  [Postgres CLI] psql missing; installing libpq..."
    brew install libpq
    if command -v psql >/dev/null 2>&1; then
        echo "✅ [Postgres CLI] psql available on PATH after install"
        return
    fi
    libpq_prefix="$(brew --prefix libpq)"
    if [ -x "${libpq_prefix}/bin/psql" ]; then
        echo "✅ [Postgres CLI] Using fallback ${libpq_prefix}/bin/psql"
        return
    fi
    echo "❌ [Postgres CLI] psql still unavailable. Add libpq bin directory to PATH and rerun."
    exit 1
}

ensure_lint_tools() {
    #R025: Ensure Go lint tooling is available.
    ensure_brew_formula "golangci-lint" "golangci-lint"
}

ensure_sast_tools() {
    #R030: Ensure SAST tooling required by this repository is available.
    ensure_brew_formula "shellcheck" "shellcheck"
    ensure_brew_formula "semgrep" "semgrep"
    ensure_brew_formula "gitleaks" "gitleaks"
}

print_final_guidance() {
    #R045: Print final local readiness guidance.
    #R050: Include MANIFOLD_DATABASE_URL reminder for DB-dependent checks.
    echo ""
    echo "✅ All prerequisites are satisfied for this repository."
    echo ""
    echo "Next commands:"
    echo "- export MANIFOLD_DATABASE_URL='postgres://user:pass@localhost:5432/manifold?sslmode=disable'"
    echo "- go test ./..."
    echo "- go test -race ./..."
    echo "- golangci-lint run"
}

main() {
    #R035: Emit explicit status for each prerequisite phase.
    #R040: Keep prerequisite installer idempotent and rerunnable.
    print_header
    ensure_homebrew
    echo ""
    ensure_go
    ensure_go_version
    ensure_postgres_cli
    ensure_lint_tools
    ensure_sast_tools
    print_final_guidance
}

main "$@"
