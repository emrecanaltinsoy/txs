package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	ilog "github.com/emrecanaltinsoy/txs/internal/log"
	"github.com/emrecanaltinsoy/txs/internal/tmux"
)

// helpers shared across commands

func isBareRepo(path string) bool {
	bareDir := filepath.Join(path, ".bare")
	if info, err := os.Stat(bareDir); err == nil && info.IsDir() {
		return true
	}
	out, err := exec.Command("git", "-C", path, "rev-parse", "--is-bare-repository").Output()
	if err != nil {
		return false
	}
	return strings.TrimSpace(string(out)) == "true"
}

type wtEntry struct {
	Path string
	Name string
}

func listWorktrees(path string) ([]wtEntry, error) {
	out, err := exec.Command("git", "-C", path, "worktree", "list", "--porcelain").Output()
	if err != nil {
		return nil, err
	}
	var result []wtEntry
	var cur string
	bare := false
	flush := func() {
		if cur != "" && !bare {
			result = append(result, wtEntry{Path: cur, Name: filepath.Base(cur)})
		}
		cur = ""
		bare = false
	}
	for _, line := range strings.Split(string(out), "\n") {
		if line == "" {
			flush()
			continue
		}
		if strings.HasPrefix(line, "worktree ") {
			cur = strings.TrimPrefix(line, "worktree ")
		} else if line == "bare" {
			bare = true
		}
	}
	flush()
	return result, nil
}

func ownsGitDir(path string) bool {
	out, err := exec.Command("git", "-C", path, "rev-parse", "--git-dir").Output()
	if err != nil {
		return false
	}
	gitDir := strings.TrimSpace(string(out))
	if !filepath.IsAbs(gitDir) {
		gitDir = filepath.Join(path, gitDir)
	}
	if resolved, err := filepath.EvalSymlinks(gitDir); err == nil {
		gitDir = resolved
	}
	return strings.HasPrefix(gitDir, path+string(os.PathSeparator)) || gitDir == path
}

func ensureSession(name, path, onCreateStr string) (created bool, err error) {
	if tmux.SessionExists(name) {
		return false, nil
	}
	fmt.Fprintf(os.Stderr, "%s\n", ilog.Green(fmt.Sprintf("Creating session %s at %s...", name, path)))
	if err := tmux.NewSession(name, path); err != nil {
		return false, fmt.Errorf("failed to create tmux session '%s': %w", name, err)
	}
	if onCreateStr != "" && !isBareRepo(path) {
		sendOnCreate(name, onCreateStr)
	}
	return true, nil
}

func sendOnCreate(session string, onCreateStr string) {
	lines := strings.Split(onCreateStr, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line != "" {
			_ = tmux.SendKeys(session, line)
		}
	}
}

func sendOnCreateLines(session string, lines []string) {
	for _, line := range lines {
		if strings.TrimSpace(line) != "" {
			_ = tmux.SendKeys(session, line)
		}
	}
}
