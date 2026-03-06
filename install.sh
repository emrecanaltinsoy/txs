#!/usr/bin/env bash
set -euo pipefail
REPO="emrecanaltinsoy/txs"
BRANCH="main"
CLONE_URL="https://github.com/$REPO.git"
TMPDIR=""
cleanup()
          {
            [[ -n $TMPDIR   ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT
if [[ -t 1 ]]; then
    GREEN='\033[0;32m' RED='\033[0;31m' DIM='\033[2m' RESET='\033[0m'
else
    GREEN='' RED='' DIM='' RESET=''
fi
info()
       {
         echo -e "$GREEN>$RESET $*"
}
error()
        {
          echo -e "${RED}error:$RESET $*"   >&2
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
TMPDIR=$(mktemp -d)
if [[ -n $TAG   ]]; then
    info "Cloning txs ($TAG)..."
    git clone --depth 1 --branch "$TAG" "$CLONE_URL" "$TMPDIR/txs" 2>&1 | tail -1
else
    info "Cloning txs (latest)..."
    git clone --depth 1 --branch "$BRANCH" "$CLONE_URL" "$TMPDIR/txs" 2>&1 | tail -1
fi
info "Installing to $PREFIX..."
make -C "$TMPDIR/txs" install PREFIX="$PREFIX"
echo ""
if command -v txs &> /dev/null; then
    info "Done! txs $(txs version 2> /dev/null || true) is ready."
elif [[ -x "$PREFIX/bin/txs"   ]]; then
    info "Done! Installed to $PREFIX/bin/txs"
    echo ""
    echo -e "${DIM}Make sure $PREFIX/bin is in your PATH:$RESET"
    echo "  export PATH=\"$PREFIX/bin:\$PATH\""
else
    error "Installation may have failed - $PREFIX/bin/txs not found."
    exit 1
fi
