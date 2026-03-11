#!/usr/bin/env bash
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd -P)"
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
assert_contains "help mentions attach command" "$help_output" "txs attach"
assert_contains "help mentions ls command" "$help_output" "txs ls"
assert_contains "help mentions kill command" "$help_output" "txs kill"
assert_contains "help mentions clone-bare command" "$help_output" "txs clone-bare"
assert_contains "help shows Session management group" "$help_output" "Session management:"
assert_contains "help shows Worktree management group" "$help_output" "Worktree management:"
assert_contains "help shows Project configuration group" "$help_output" "Project configuration:"
assert_contains "help mentions wt add command" "$help_output" "txs wt add"
assert_contains "help mentions wt remove command" "$help_output" "txs wt remove"
assert_contains "help mentions wt list command" "$help_output" "txs wt list"
assert_contains "help shows aliases section" "$help_output" "ALIASES:"
assert_contains "help shows list alias" "$help_output" "list      -> ls"
echo -e "${BOLD}test: unknown command$RESET"
unknown_output=$("$TXS" nonexistent 2>&1) && ec=0 || ec=$?
assert_exit_code "unknown command exits non-zero" "1" "$ec"
assert_contains "unknown command shows error" "$unknown_output" "Unknown command"
echo -e "${BOLD}test: ls invalid filter$RESET"
ls_output=$("$TXS" ls invalid 2>&1) && ec=0 || ec=$?
assert_exit_code "ls invalid filter exits non-zero" "1" "$ec"
assert_contains "ls invalid filter shows error" "$ls_output" "Unknown filter"
echo -e "${BOLD}test: config invalid target$RESET"
config_output=$("$TXS" config invalid 2>&1) && ec=0 || ec=$?
assert_exit_code "config invalid target exits non-zero" "1" "$ec"
assert_contains "config invalid target shows error" "$config_output" "Unknown config target"
echo -e "${BOLD}test: wt invalid subcommand$RESET"
wt_output=$("$TXS" wt invalid 2>&1) && ec=0 || ec=$?
assert_exit_code "wt invalid subcommand exits non-zero" "1" "$ec"
assert_contains "wt invalid subcommand shows error" "$wt_output" "Unknown wt subcommand"
echo -e "${BOLD}test: wt add missing branch$RESET"
wt_add_output=$("$TXS" wt add 2>&1) && ec=0 || ec=$?
assert_exit_code "wt add missing branch exits non-zero" "1" "$ec"
assert_contains "wt add missing branch shows error" "$wt_add_output" "Missing branch name"
echo -e "${BOLD}test: wt remove missing branch$RESET"
wt_rm_output=$("$TXS" wt remove 2>&1) && ec=0 || ec=$?
assert_exit_code "wt remove missing branch exits non-zero" "1" "$ec"
assert_contains "wt remove missing branch shows error" "$wt_rm_output" "Missing branch name"
echo -e "${BOLD}test: aliases route correctly$RESET"
# 'list' should behave like 'ls' (both produce the same output)
list_output=$("$TXS" list 2>&1) && ec=0 || ec=$?
ls_output=$("$TXS" ls 2>&1) && ec=0 || ec=$?
assert_eq "list and ls produce same output" "$list_output" "$ls_output"
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
echo -e "${BOLD}test: get_txs_setting$RESET"
cat > "$TMPDIR_TEST/config" << 'CONF'
# txs settings
auto_add_clone = true
some_other = hello world
CONF
TXS_SETTINGS_FILE="$TMPDIR_TEST/config"
setting_val=$(get_txs_setting "auto_add_clone")
assert_eq "reads auto_add_clone setting" "true" "$setting_val"
setting_val=$(get_txs_setting "some_other")
assert_eq "reads some_other setting" "hello world" "$setting_val"
setting_val=$(get_txs_setting "nonexistent")
assert_eq "missing key returns empty" "" "$setting_val"
TXS_SETTINGS_FILE="$TMPDIR_TEST/nonexistent_file"
setting_val=$(get_txs_setting "auto_add_clone")
assert_eq "missing settings file returns empty" "" "$setting_val"
echo -e "${BOLD}test: fzf_height setting$RESET"
cat > "$TMPDIR_TEST/config" << 'CONF'
fzf_height = 80%
CONF
TXS_SETTINGS_FILE="$TMPDIR_TEST/config"
fzf_h=$(get_txs_setting "fzf_height")
assert_eq "reads fzf_height from settings" "80%" "$fzf_h"
TXS_SETTINGS_FILE="$TMPDIR_TEST/nonexistent_file"
fzf_h=$(get_txs_setting "fzf_height")
_default="${fzf_h:-50%}"
assert_eq "fzf_height defaults to 50% when missing" "50%" "$_default"
echo ""
echo -e "${BOLD}Results: $PASS/$TOTAL passed, $FAIL failed$RESET"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
