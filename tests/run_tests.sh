#!/usr/bin/env bash
set -uo pipefail
TESTS_DIR="$(dirname "$(readlink -f "$0")")"
PROJECT_ROOT="$(dirname "$TESTS_DIR")"
PASS=0
FAIL=0
TOTAL=0
source "$PROJECT_ROOT/lib/log.sh"
assert_eq()
{
    local description="$1"
    local expected="$2"
    local actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ $expected == "$actual" ]]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS$RESET $description"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL$RESET $description"
        echo -e "       expected: $expected"
        echo -e "       actual:   $actual"
    fi
}
assert_contains()
{
    local description="$1"
    local haystack="$2"
    local needle="$3"
    TOTAL=$((TOTAL + 1))
    if [[ $haystack == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS$RESET $description"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL$RESET $description"
        echo -e "       expected to contain: $needle"
        echo -e "       got: $haystack"
    fi
}
assert_exit_code()
{
    local description="$1"
    local expected="$2"
    local actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ $expected == "$actual" ]]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS$RESET $description"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL$RESET $description"
        echo -e "       expected exit code: $expected"
        echo -e "       actual exit code:   $actual"
    fi
}
TMPDIR_INSTALL=$(mktemp -d)
cleanup()
{
    rm -rf "$TMPDIR_INSTALL" "${TMPDIR_TEST:-}"
}
trap cleanup EXIT
mkdir -p "$TMPDIR_INSTALL/bin" "$TMPDIR_INSTALL/lib/txs"
cp "$PROJECT_ROOT/bin/txs" "$TMPDIR_INSTALL/bin/txs"
chmod +x "$TMPDIR_INSTALL/bin/txs"
for f in "$PROJECT_ROOT"/lib/*.sh; do
    cp "$f" "$TMPDIR_INSTALL/lib/txs/"
done
TXS="$TMPDIR_INSTALL/bin/txs"
echo -e "${BOLD}test: version$RESET"
source "$PROJECT_ROOT/lib/config.sh"
version_output=$("$TXS" version 2>&1) || true
assert_contains "txs version prints version string" "$version_output" "$TXS_VERSION"
assert_contains "txs --version prints version string" "$("$TXS" --version 2>&1 || true)" "$TXS_VERSION"
assert_contains "txs -v prints version string" "$("$TXS" -v 2>&1 || true)" "$TXS_VERSION"
echo -e "${BOLD}test: help$RESET"
help_output=$("$TXS" help 2>&1) || true
assert_contains "help mentions USAGE" "$help_output" "USAGE"
assert_contains "help mentions list command" "$help_output" "txs list"
assert_contains "help mentions worktrees command" "$help_output" "txs worktrees"
assert_contains "help mentions create command" "$help_output" "txs create"
assert_contains "help mentions kill command" "$help_output" "txs kill"
assert_contains "help mentions clone-bare command" "$help_output" "txs clone-bare"
echo -e "${BOLD}test: unknown command$RESET"
unknown_output=$("$TXS" nonexistent 2>&1) && ec=0 || ec=$?
assert_exit_code "unknown command exits non-zero" "1" "$ec"
assert_contains "unknown command shows error" "$unknown_output" "Unknown command"
echo -e "${BOLD}test: create missing argument$RESET"
create_output=$("$TXS" create 2>&1) && ec=0 || ec=$?
assert_exit_code "create without arg exits non-zero" "1" "$ec"
assert_contains "create without arg shows error" "$create_output" "Missing project name"
echo -e "${BOLD}test: kill missing argument$RESET"
kill_output=$("$TXS" kill 2>&1) && ec=0 || ec=$?
assert_exit_code "kill without arg exits non-zero" "1" "$ec"
assert_contains "kill without arg shows error" "$kill_output" "Missing session name"
echo -e "${BOLD}test: config parser$RESET"
TMPDIR_TEST=$(mktemp -d)
cat > "$TMPDIR_TEST/projects.conf" << 'CONF'
[DEFAULT]
on_create = echo default

[myproject]
path = ~/projects/test
session_name = test-session
on_create = nvim .

[another]
path = /tmp/another
CONF
CONFIG_FILE="$TMPDIR_TEST/projects.conf"
declare -A PROJECT_PATH=()
declare -A PROJECT_SESSION_NAME=()
declare -A PROJECT_ON_CREATE=()
declare -a PROJECT_ORDER=()
declare -A DEFAULTS=()
parse_config
assert_eq "parses project count" "2" "${#PROJECT_ORDER[@]}"
assert_eq "parses first project name" "myproject" "${PROJECT_ORDER[0]}"
assert_eq "parses second project name" "another" "${PROJECT_ORDER[1]}"
#shellcheck disable=SC2088
assert_eq "parses project path" "~/projects/test" "${PROJECT_PATH[myproject]}"
assert_eq "parses session_name" "test-session" "${PROJECT_SESSION_NAME[myproject]}"
assert_eq "parses on_create" "nvim ." "${PROJECT_ON_CREATE[myproject]}"
assert_eq "parses default on_create" "echo default" "${DEFAULTS[on_create]}"
another_on_create=$(get_project_prop "another" "on_create")
assert_eq "fallback to DEFAULT on_create" "echo default" "$another_on_create"
another_session=$(get_project_prop "another" "session_name")
assert_eq "session_name defaults to section name" "another" "$another_session"
#shellcheck disable=SC2088
expanded=$(expand_path "~/foo/bar")
assert_eq "expand_path expands tilde" "$HOME/foo/bar" "$expanded"
echo -e "${BOLD}test: config parser continuation lines$RESET"
cat > "$TMPDIR_TEST/projects.conf" << 'CONF'
[multi]
path = ~/multi
on_create = tmux split-window -v
    nvim .
CONF
CONFIG_FILE="$TMPDIR_TEST/projects.conf"
declare -A PROJECT_PATH=()
declare -A PROJECT_SESSION_NAME=()
declare -A PROJECT_ON_CREATE=()
declare -a PROJECT_ORDER=()
declare -A DEFAULTS=()
parse_config
multi_on_create=$(get_project_prop "multi" "on_create")
assert_contains "continuation line appended" "$multi_on_create" "nvim ."
assert_contains "first line preserved" "$multi_on_create" "tmux split-window -v"
echo ""
echo -e "${BOLD}Results: $PASS/$TOTAL passed, $FAIL failed$RESET"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
