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
assert_contains "help shows Worktree management group" "$help_output" "Worktree management"
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
wt_add_output=$("$TXS" wt add 2>&1 < /dev/null) && ec=0 || ec=$?
assert_exit_code "wt add missing branch exits non-zero" "1" "$ec"
assert_contains "wt add missing branch shows error" "$wt_add_output" "Missing branch name"
echo -e "${BOLD}test: wt remove missing branch$RESET"
wt_rm_output=$("$TXS" wt remove 2>&1 < /dev/null) && ec=0 || ec=$?
assert_exit_code "wt remove missing branch exits non-zero" "1" "$ec"
assert_contains "wt remove missing branch shows error" "$wt_rm_output" "Missing branch name"
echo -e "${BOLD}test: wt add outside git repo$RESET"
wt_add_output=$(cd /tmp && "$TXS" wt add 2>&1) && ec=0 || ec=$?
assert_exit_code "wt add outside git repo exits non-zero" "1" "$ec"
assert_contains "wt add outside git repo shows error" "$wt_add_output" "Not inside a git repository"
echo -e "${BOLD}test: wt remove outside git repo$RESET"
wt_rm_output=$(cd /tmp && "$TXS" wt remove 2>&1) && ec=0 || ec=$?
assert_exit_code "wt remove outside git repo exits non-zero" "1" "$ec"
assert_contains "wt remove outside git repo shows error" "$wt_rm_output" "Not inside a git repository"
echo -e "${BOLD}test: wt list outside git repo$RESET"
wt_ls_output=$(cd /tmp && "$TXS" wt list 2>&1) && ec=0 || ec=$?
assert_exit_code "wt list outside git repo exits non-zero" "1" "$ec"
assert_contains "wt list outside git repo shows error" "$wt_ls_output" "Not inside a git repository"
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
_CONFIG_LOADED=false
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
_CONFIG_LOADED=false
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
# ---------------------------------------------------------------------------
# 6.5: require_arg -- missing arguments
# ---------------------------------------------------------------------------
echo -e "${BOLD}test: require_arg missing arguments$RESET"
remove_output=$("$TXS" remove 2>&1) && ec=0 || ec=$?
assert_exit_code "txs remove with no arg exits non-zero" "1" "$ec"
assert_contains "txs remove with no arg shows error" "$remove_output" "Missing project name"
clone_output=$("$TXS" clone-bare 2>&1) && ec=0 || ec=$?
assert_exit_code "txs clone-bare with no arg exits non-zero" "1" "$ec"
assert_contains "txs clone-bare with no arg shows error" "$clone_output" "Missing repository URL"
# ---------------------------------------------------------------------------
# 6.1: cmd_add / cmd_remove
# ---------------------------------------------------------------------------
echo -e "${BOLD}test: cmd_add$RESET"
TMPDIR_TEST=$(mktemp -d)
CONFIG_FILE="$TMPDIR_TEST/projects.conf"
_CONFIG_LOADED=false
# Source git.sh for functions used by commands.sh
source "$PROJECT_ROOT/lib/git.sh"
source "$PROJECT_ROOT/lib/commands.sh"
# Create a directory to add
mkdir -p "$TMPDIR_TEST/my-project"
add_output=$(cmd_add "$TMPDIR_TEST/my-project" 2>&1) || true
assert_contains "cmd_add reports success" "$add_output" "Added project"
# Verify file exists
[[ -f $CONFIG_FILE ]] && _file_exists="true" || _file_exists="false"
assert_eq "config file exists after add" "true" "$_file_exists"
# Parse and verify
_CONFIG_LOADED=false
declare -A PROJECT_PATH=()
declare -A PROJECT_SESSION_NAME=()
declare -A PROJECT_ON_CREATE=()
declare -a PROJECT_ORDER=()
declare -A DEFAULTS=()
parse_config
assert_eq "added project appears in config" "1" "${#PROJECT_ORDER[@]}"
assert_eq "added project name is correct" "my-project" "${PROJECT_ORDER[0]}"
_add_key="my-project"
assert_eq "added project path is correct" "$TMPDIR_TEST/my-project" "${PROJECT_PATH[$_add_key]}"
echo -e "${BOLD}test: cmd_add duplicate detection$RESET"
dup_output=$(cmd_add "$TMPDIR_TEST/my-project" 2>&1) && ec=0 || ec=$?
assert_exit_code "duplicate add exits non-zero" "1" "$ec"
assert_contains "duplicate add shows error" "$dup_output" "already exists"
echo -e "${BOLD}test: cmd_add nonexistent path$RESET"
bad_output=$(cmd_add "$TMPDIR_TEST/no-such-dir" 2>&1) && ec=0 || ec=$?
assert_exit_code "add nonexistent path exits non-zero" "1" "$ec"
assert_contains "add nonexistent path shows error" "$bad_output" "does not exist"
echo -e "${BOLD}test: cmd_remove$RESET"
rm_output=$(cmd_remove "my-project" 2>&1) || true
assert_contains "cmd_remove reports success" "$rm_output" "Removed project"
# Parse and verify it's gone
_CONFIG_LOADED=false
declare -A PROJECT_PATH=()
declare -A PROJECT_SESSION_NAME=()
declare -A PROJECT_ON_CREATE=()
declare -a PROJECT_ORDER=()
declare -A DEFAULTS=()
parse_config
assert_eq "removed project gone from config" "0" "${#PROJECT_ORDER[@]}"
echo -e "${BOLD}test: cmd_remove nonexistent project$RESET"
rm_bad_output=$(cmd_remove "nonexistent" 2>&1) && ec=0 || ec=$?
assert_exit_code "remove nonexistent exits non-zero" "1" "$ec"
assert_contains "remove nonexistent shows error" "$rm_bad_output" "not found"
# ---------------------------------------------------------------------------
# 6.4: Special characters in paths (spaces)
# ---------------------------------------------------------------------------
echo -e "${BOLD}test: cmd_add with spaces in path$RESET"
CONFIG_FILE="$TMPDIR_TEST/projects2.conf"
_CONFIG_LOADED=false
mkdir -p "$TMPDIR_TEST/cool project"
add_space_output=$(cmd_add "$TMPDIR_TEST/cool project" 2>&1) || true
assert_contains "add with spaces reports success" "$add_space_output" "Added project"
# The name should have space replaced with -
_CONFIG_LOADED=false
declare -A PROJECT_PATH=()
declare -A PROJECT_SESSION_NAME=()
declare -A PROJECT_ON_CREATE=()
declare -a PROJECT_ORDER=()
declare -A DEFAULTS=()
parse_config
assert_eq "space in name sanitized" "cool-project" "${PROJECT_ORDER[0]}"
_space_key="cool-project"
assert_eq "path with spaces preserved" "$TMPDIR_TEST/cool project" "${PROJECT_PATH[$_space_key]}"
# ---------------------------------------------------------------------------
# 6.3: clone-bare (integration test with local repo)
# ---------------------------------------------------------------------------
echo -e "${BOLD}test: clone-bare$RESET"
# Create a local "origin" repo
_origin="$TMPDIR_TEST/origin-repo"
mkdir -p "$_origin"
git -C "$_origin" init --bare > /dev/null 2>&1
# Add a commit so there's a branch
_work="$TMPDIR_TEST/origin-work"
git clone "$_origin" "$_work" > /dev/null 2>&1
git -C "$_work" config user.email "test@test.com"
git -C "$_work" config user.name "Test"
git -C "$_work" commit --allow-empty -m "initial" > /dev/null 2>&1
git -C "$_work" push origin main > /dev/null 2>&1 || git -C "$_work" push origin master > /dev/null 2>&1
# Detect which branch was pushed
_default_branch=$(git -C "$_origin" branch | sed 's/^[* ]*//' | head -n1)
# Use a fresh config for clone-bare
CONFIG_FILE="$TMPDIR_TEST/clone-projects.conf"
TXS_SETTINGS_FILE="$TMPDIR_TEST/clone-settings"
printf 'auto_add_clone = true\n' > "$TXS_SETTINGS_FILE"
_CONFIG_LOADED=false
# Run clone-bare from a temp working directory
_clone_dir="$TMPDIR_TEST/clone-test"
mkdir -p "$_clone_dir"
clone_output=$(cd "$_clone_dir" && cmd_clone_bare "$_origin" "myrepo" 2>&1) || true
assert_contains "clone-bare reports success" "$clone_output" "Success!"
# Verify directory structure
[[ -d "$_clone_dir/myrepo/.bare" ]] && _bare="true" || _bare="false"
assert_eq "bare directory exists" "true" "$_bare"
[[ -f "$_clone_dir/myrepo/.git" ]] && _gitfile="true" || _gitfile="false"
assert_eq ".git file exists" "true" "$_gitfile"
# Verify worktree was created
[[ -d "$_clone_dir/myrepo/myrepo.$_default_branch" ]] && _wt="true" || _wt="false"
assert_eq "default worktree created" "true" "$_wt"
# Verify auto-add to config
[[ -f $CONFIG_FILE ]] && _added="true" || _added="false"
assert_eq "clone-bare auto-added to config" "true" "$_added"
echo ""
echo -e "${BOLD}Results: $PASS/$TOTAL passed, $FAIL failed$RESET"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
