#!/usr/bin/env bash
set -euo pipefail
REPO="emrecanaltinsoy/txs"
BRANCH="main"
CLONE_URL="https://github.com/$REPO.git"
TXS_TMPDIR=""
cleanup()
{
    [[ -n $TXS_TMPDIR ]] && rm -rf "$TXS_TMPDIR"
}
trap cleanup EXIT
if [[ -t 1 ]]; then
    GREEN='\033[0;32m' RED='\033[0;31m' DIM='\033[2m' RESET='\033[0m'
else
    GREEN='' RED='' DIM='' RESET=''
fi

# Standalone script -- cannot source lib/log.sh before cloning the repo
info()
{
    printf '%b %b\n' "${GREEN}>" "${RESET}$*"
}
error()
{
    printf '%b %b\n' "${RED}Error:" "${RESET}$*" >&2
}
for cmd in git make install; do
    if ! command -v "$cmd" &> /dev/null; then
        error "'$cmd' is required but not found."
        exit 1
    fi
done
PREFIX="${PREFIX:-$HOME/.local}"
TAG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --prefix=*)
            PREFIX="${1#--prefix=}"
            shift
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --tag=*)
            TAG="${1#--tag=}"
            shift
            ;;
        -h | --help)
            echo "Usage: install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --prefix DIR   Installation prefix (default: $HOME/.local)"
            echo "  --tag TAG      Install a specific version tag (default: latest)"
            echo "  -h, --help     Show this message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done
TXS_TMPDIR=$(mktemp -d)
if [[ -n $TAG ]]; then
    info "Cloning txs ($TAG)..."
    if ! git clone --depth 1 --branch "$TAG" "$CLONE_URL" "$TXS_TMPDIR/txs"; then
        error "Failed to clone txs (tag: $TAG)"
        exit 1
    fi
else
    info "Cloning txs (latest)..."
    if ! git clone --depth 1 --branch "$BRANCH" "$CLONE_URL" "$TXS_TMPDIR/txs"; then
        error "Failed to clone txs"
        exit 1
    fi
fi
info "Installing to $PREFIX..."
if ! make -C "$TXS_TMPDIR/txs" install PREFIX="$PREFIX"; then
    error "Installation failed."
    exit 1
fi
echo ""
if command -v txs &> /dev/null; then
    info "Done! txs $(txs version 2> /dev/null || true) is ready."
elif [[ -x "$PREFIX/bin/txs" ]]; then
    info "Done! Installed to $PREFIX/bin/txs"
    echo ""
    printf '%b\n' "${DIM}Make sure $PREFIX/bin is in your PATH:$RESET"
    echo "  export PATH=\"$PREFIX/bin:\$PATH\""
else
    error "Installation may have failed - $PREFIX/bin/txs not found."
    exit 1
fi
