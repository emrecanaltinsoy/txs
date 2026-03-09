# txs

<p align="center">
  <a href="https://github.com/emrecanaltinsoy/txs/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/emrecanaltinsoy/txs/ci.yml?logo=github&label=ci-check" alt="GitHub Actions Workflow Status"></a>
  <a href="https://github.com/emrecanaltinsoy/txs/releases"><img src="https://img.shields.io/github/v/release/emrecanaltinsoy/txs?display_name=release" alt="GitHub Release"></a>
  <a href="https://github.com/emrecanaltinsoy/txs/blob/main/LICENSE"><img src="https://img.shields.io/github/license/emrecanaltinsoy/txs" alt="GitHub License"></a>
</p>

A command-line tool to manage tmux sessions from predefined project directories.
Inspired by [ThePrimeagen's tmux-sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer) and [jrmoulton's tmux-sessionizer](https://github.com/jrmoulton/tmux-sessionizer), tailored to my workflow for managing multiple projects in separate tmux sessions with custom layouts.

txs lets you define your projects in a simple INI-style configuration file and
quickly create, switch to, list, or kill tmux sessions. It includes an
interactive fuzzy-finder picker powered by fzf, with automatic tmux popup
support.

It also includes a helper command to clone repositories as bare repos with a
default worktree so you can keep using Git worktrees cleanly.

## Features

- **Interactive session picker** -- fuzzy-find and switch between projects with fzf
- **Tmux popup support** -- automatically launches in a floating tmux popup when run inside tmux
- **INI-style configuration** -- define projects with paths, custom session names, and on-create commands
- **Multi-line on_create** -- run multiple commands when a session is first created
- **Context-aware** -- works both inside and outside tmux
- **Shell completions** -- tab completion for Bash and Zsh

## Dependencies

| Dependency | Required |
|------------|----------|
| bash       | Yes      |
| tmux       | Yes      |
| fzf        | No (needed for interactive mode) |

## Installation

### Quick install

```sh
curl -fsSL https://raw.githubusercontent.com/emrecanaltinsoy/txs/main/install.sh | bash
```

This clones the repo, runs `make install`, and cleans up. It installs to
`$HOME/.local` by default. You can pass options after `bash -s --`:

```sh
# Custom prefix
curl -fsSL https://raw.githubusercontent.com/emrecanaltinsoy/txs/main/install.sh | bash -s -- --prefix /usr/local

# Specific version
curl -fsSL https://raw.githubusercontent.com/emrecanaltinsoy/txs/main/install.sh | bash -s -- --tag v0.1.0
```

### Manual install

```sh
git clone https://github.com/emrecanaltinsoy/txs.git
cd txs
make install
```

You can change the prefix:

```sh
make install PREFIX=/usr/local
```

To enable shell completions, add one of these to your shell rc file:

```sh
# zsh
[[ -f "$HOME/.local/share/txs/completions/txs.zsh" ]] && source "$HOME/.local/share/txs/completions/txs.zsh"

# bash
[[ -f "$HOME/.local/share/txs/completions/txs.bash" ]] && source "$HOME/.local/share/txs/completions/txs.bash"
```

## Uninstallation

```sh
make uninstall
```

This removes txs but keeps your configuration.

## Configuration

txs reads project definitions from `$HOME/.config/txs/projects.conf`. An example
config is installed automatically on first install.

```ini
[DEFAULT]

[my-project]
path = ~/projects/my-project
session_name = myproj
on_create = nvim .

[webapp]
path = ~/projects/webapp
on_create = tmux split-window -v -l 20
    tmux split-window -h -d
    tmux send-keys -t 3 "npm run dev" Enter
    tmux select-pane -t 1
    nvim .
```

### Configuration keys

| Key            | Required | Description                                                    |
|----------------|----------|----------------------------------------------------------------|
| `path`         | Yes      | Directory path for the project (`~` is expanded)               |
| `session_name` | No       | Custom tmux session name (defaults to section name)            |
| `on_create`    | No       | Commands to run after session creation (supports multi-line)   |

The `[DEFAULT]` section provides fallback values for all projects. Dots in
session names are automatically replaced with dashes.

## Usage

```
txs                  Interactive fuzzy-finder session picker
txs create <name>    Create or switch to a session for a project
txs add [path]       Add a directory to the config (default: current dir)
txs remove <name>    Remove a project from the config
txs clone-bare <url> [name]
                     Clone as bare repo + create default branch worktree
txs config           Open the config file in $EDITOR
txs kill <name>      Kill a tmux session
txs list             List active tmux sessions
txs worktrees [name] List/switch git worktrees (fuzzy finder when no arg)
txs projects         List all configured projects and their status
txs help             Show help
```

### Clone Bare For Worktrees

`txs clone-bare <repo-url> [folder-name]` creates a repository layout suited
for worktree-heavy workflows:

- clones the repository as a bare repo into `.bare/`
- writes `.git` to point at `./.bare`
- fetches remote branches with a full branch refspec
- creates a default branch worktree (origin HEAD, then `main`, then `master`)

Example:

```sh
txs clone-bare git@github.com:org/repo.git
```

This creates `./repo` (or your custom folder name), stores git data in
`./repo/.bare`, and checks out the default branch into `./repo/<branch>`.

### Environment variables

| Variable           | Description                                                                 |
|--------------------|-----------------------------------------------------------------------------|
| `TXS_POPUP`        | When set to `1`, txs will not launch in a tmux popup even if run inside tmux. This is useful when you want to control the display behavior yourself. |
| `TXS_POPUP_WIDTH`  | Width of tmux popup (default: 80%)                                          |
| `TXS_POPUP_HEIGHT` | Height of tmux popup (default: 70%)                                         |

## Keybindings

I mainly access txs through keybindings in tmux and Neovim rather than running
it directly from the shell. However, you can use it in any terminal. Here are some example keybindings:

### tmux

```sh
bind-key -r a run-shell "txs"
```

### Neovim

If not inside tmux, this keymap will not work, but it won't cause any issues either. If inside tmux, it will open the tmux popup with the interactive session picker.

```lua
vim.keymap.set({ "n" }, "<leader>tt", "<cmd>silent !txs<cr>", { desc = "Start txs" })
```

## Pairing with tmuxifier

txs pairs well with [tmuxifier](https://github.com/jimeh/tmuxifier). While
tmuxifier manages complex window and pane layouts through dedicated layout
files, txs can complement it by using `on_create` to define how sessions should
start, whether that means loading a tmuxifier layout, opening an editor, or
spinning up dev servers.

## License

[MIT](LICENSE)
