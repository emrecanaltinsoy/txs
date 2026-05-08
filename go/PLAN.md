# Go Rewrite Plan

## Overview

Rewrite `txs` as a Go binary that is a drop-in replacement for the current shell
implementation. Same config files, same CLI interface, same behavior.

The shell implementation stays untouched under `lib/` and `bin/` during the
rewrite. The Go code lives in `go/`. When the Go version is complete, the
top-level `Makefile` and `install.sh` are updated to point to the Go binary.

---

## Repository Layout

```
txs/
├── go/                        ← new Go implementation
│   ├── main.go
│   ├── go.mod                 (module: github.com/emrecanaltinsoy/txs)
│   ├── go.sum
│   ├── cmd/
│   │   ├── root.go            cobra root + default interactive command
│   │   ├── attach.go
│   │   ├── switch.go
│   │   ├── ls.go
│   │   ├── kill.go
│   │   ├── wt.go              (wt add / remove / list)
│   │   ├── add.go
│   │   ├── remove.go
│   │   ├── clone_bare.go
│   │   └── config.go
│   ├── internal/
│   │   ├── config/            projects.conf + settings parsing
│   │   ├── tmux/              exec wrappers for all tmux operations
│   │   ├── git/               bare repo detection, worktrees, depth scan
│   │   ├── ui/                fzf subprocess integration + entry formatting
│   │   └── log/               colored terminal output
│   └── Makefile               build / install / lint / test
├── lib/                       ← existing shell implementation (kept)
├── bin/
└── ...
```

---

## Dependencies

| Package | Purpose |
|---|---|
| `github.com/spf13/cobra` | CLI framework, subcommands, auto shell completions |
| `gopkg.in/ini.v1` | `projects.conf` parsing/writing (multi-line values, section management) |

Everything else (`tmux`, `git`, `fzf` subprocess calls, path handling, file I/O)
uses the Go standard library only.

---

## Internal Packages

### `internal/config`

- `ParseProjects(path string) ([]Project, Defaults, error)` — load
  `projects.conf` via `gopkg.in/ini.v1`; handle `[DEFAULT]`, `~` expansion,
  session name sanitization, `max_depth`, multi-line `on_create`; deduplicate
  sections keeping the last occurrence
- `ParseSettings(path string) (Settings, error)` — load flat `config` file
- `AddProject(path, name string) error` — append section and save
- `RemoveProject(name string) error` — delete section and save
- Config file paths follow XDG (`$XDG_CONFIG_HOME/txs/` or `~/.config/txs/`)

**Types:**

```go
type Project struct {
    Name        string
    Path        string
    SessionName string
    OnCreate    []string
    MaxDepth    int
}

type Defaults struct {
    SessionName string
    OnCreate    []string
}

type Settings struct {
    AutoAddClone bool
    FzfHeight    string
}
```

### `internal/tmux`

Thin wrappers around `exec.Command("tmux", ...)`:

- `SessionExists(name string) bool`
- `NewSession(name, path string) error`
- `AttachOrSwitch(name string) error` — detects `$TMUX` env var
- `ListSessions() ([]string, error)`
- `KillSession(name string) error`
- `ListWindows(session string) ([]Window, error)`
- `KillWindow(session, window string) error`
- `SendKeys(session, keys string) error`
- `ListPanes() ([]Pane, error)` — used for active worktree detection
- `FindWindowByPath(session, path string) (string, error)`
- `SanitizeName(s string) string` — replace `.` and `:` with `_`
- `IsInsideTmux() bool`
- `FetchSessionWindows() (map[string]string, error)` — session → window list string

### `internal/git`

- `IsBareRepo(path string) bool` — `.bare/` layout or `--is-bare-repository`
- `ListWorktrees(path string) ([]Worktree, error)` — parse `git worktree list --porcelain`, skip bare entries
- `ScanDepth(root string, maxDepth int) ([]DepthRepo, error)` — recursive scan, stops at git repos, skips hidden dirs
- `GetRepoInfo(cwd string) (RepoInfo, error)` — root + type (`bare`/`normal`) from CWD
- `WorktreePath(root, branch string, bare bool) string` — inside repo for bare, sibling for normal
- `RepoNameFromURL(url string) string`
- `GetActiveWorktrees(panes []Pane) map[string]string` — pane path → session name

**Types:**

```go
type Worktree struct {
    Path string
    Name string
}

type DepthRepo struct {
    Path string
    Name string
}

type RepoInfo struct {
    Root string
    Type string // "bare" or "normal"
}
```

### `internal/ui`

- `RunFzf(entries []Entry, opts FzfOpts) (*Entry, error)` — pipes formatted
  entries to fzf stdin, reads selected line, parses it back to `Entry`
- Entry types and display formatting (active `*`/` `, inactive `+`, depth
  prefix `[project]`)
- Deduplication logic (explicit path set, depth last-wins) shared between
  interactive and switch commands

### `internal/log`

- `Info(msg string)` — green `>` prefix, stdout
- `Warn(msg string)` — yellow `Warning:` prefix, stderr
- `Error(msg string)` — red `Error:` prefix, stderr
- Colors auto-disabled when stdout is not a TTY

---

## Commands

| Shell command | Go file | Notes |
|---|---|---|
| `txs` (no args) | `cmd/root.go` | default cobra `Run`, launches interactive picker |
| `txs attach [name] [wt]` | `cmd/attach.go` | |
| `txs switch` | `cmd/switch.go` | active sessions only |
| `txs ls [filter]` | `cmd/ls.go` | filters: `sessions`, `projects`, `worktrees` |
| `txs kill [name]` | `cmd/kill.go` | `kill window` as sub-argument |
| `txs wt add/remove/list` | `cmd/wt.go` | |
| `txs add [path]` | `cmd/add.go` | |
| `txs remove <name>` | `cmd/remove.go` | |
| `txs clone-bare <url>` | `cmd/clone_bare.go` | |
| `txs config [target]` | `cmd/config.go` | opens `$EDITOR` |

Aliases preserved: `list` = `ls`, `sessions` = `ls sessions`,
`projects` = `ls projects`.

---

## Shell Completions

Cobra generates bash/zsh/fish completions via `txs completion bash` etc.,
replacing the handwritten `completions/txs.bash` and `completions/txs.zsh`.

The `go/Makefile` includes a `generate-completions` target:

```makefile
generate-completions:
    go run . completion bash > ../completions/txs.bash
    go run . completion zsh  > ../completions/txs.zsh
```

---

## Build & Install

`go/Makefile`:

```makefile
build:
    go build -o ../bin/txs-go ./...

install:
    install -m755 ../bin/txs-go $(PREFIX)/bin/txs

test:
    go test ./...

lint:
    golangci-lint run

generate-completions:
    go run . completion bash > ../completions/txs.bash
    go run . completion zsh  > ../completions/txs.zsh
```

Once the Go version is stable:
- Top-level `Makefile` `install` target switches from copying shell files to
  building from `go/`
- `install.sh` updated to run `make -C go install` instead

---

## Testing Strategy

- **Unit tests** for `internal/config` (parser edge cases, multi-line
  `on_create`, dedup, DEFAULT fallback), `internal/git` (bare detection, depth
  scan), `internal/tmux` (name sanitization)
- **Integration tests** using `os/exec` against a temp directory, mirroring all
  existing `tests/run_tests.sh` cases 1:1
- Run with `go test ./...`

---

## Implementation Order

1. Scaffold `go/` directory, `go.mod`, cobra root, `Makefile`
2. `internal/config` — parser + writer (most foundational)
3. `internal/tmux` — thin exec wrappers
4. `internal/git` — bare repo, worktrees, depth scan
5. `internal/log` — trivial
6. `cmd/ls`, `cmd/attach` — first visible commands, validates the full stack
7. `internal/ui` + `cmd/root` (interactive), `cmd/switch`
8. `cmd/kill`, `cmd/wt`, `cmd/add`, `cmd/remove`, `cmd/clone_bare`, `cmd/config`
9. Generate shell completions
10. Update top-level `Makefile` and `install.sh`
11. Port all tests
