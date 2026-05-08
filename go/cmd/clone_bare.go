package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/emrecanaltinsoy/txs/internal/config"
	ilog "github.com/emrecanaltinsoy/txs/internal/log"
	"github.com/spf13/cobra"
)

var cloneBareCmd = &cobra.Command{
	Use:   "clone-bare <url> [name]",
	Short: "Clone a repository as a bare repo with worktree setup",
	Args: func(cmd *cobra.Command, args []string) error {
		if len(args) < 1 {
			return fmt.Errorf("Missing repository URL")
		}
		if len(args) > 2 {
			return fmt.Errorf("accepts at most 2 args, received %d", len(args))
		}
		return nil
	},
	RunE: func(cmd *cobra.Command, args []string) error {
		url := args[0]
		name := ""
		if len(args) > 1 {
			name = args[1]
		} else {
			name = repoNameFromURL(url)
		}

		cwd, err := os.Getwd()
		if err != nil {
			return err
		}
		root := filepath.Join(cwd, name)

		if err := os.MkdirAll(root, 0o755); err != nil {
			return err
		}

		// Clone as bare into .bare/
		bareDir := filepath.Join(root, ".bare")
		ilog.Info(fmt.Sprintf("Cloning %s into %s", url, root))
		cloneCmd := exec.Command("git", "clone", "--bare", url, bareDir)
		cloneCmd.Stdout = os.Stdout
		cloneCmd.Stderr = os.Stderr
		if err := cloneCmd.Run(); err != nil {
			return fmt.Errorf("git clone failed: %w", err)
		}

		// Write .git file stub
		gitFile := filepath.Join(root, ".git")
		if err := os.WriteFile(gitFile, []byte("gitdir: ./.bare\n"), 0o644); err != nil {
			return err
		}

		// Set fetch config so remote branches are tracked
		_ = exec.Command("git", "-C", root, "config",
			"remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*").Run()
		_ = exec.Command("git", "-C", root, "fetch", "origin").Run()

		// Detect default branch
		branch := detectDefaultBranch(root)
		ilog.Info(fmt.Sprintf("Default branch: %s", branch))

		// Create default worktree
		wtPath := filepath.Join(root, name+"."+branch)
		wtCmd := exec.Command("git", "-C", root, "worktree", "add", wtPath, branch)
		wtCmd.Stdout = os.Stdout
		wtCmd.Stderr = os.Stderr
		if err := wtCmd.Run(); err != nil {
			return fmt.Errorf("failed to create worktree: %w", err)
		}

		// Lock the default worktree
		_ = exec.Command("git", "-C", root, "worktree", "lock", wtPath).Run()

		ilog.Info(fmt.Sprintf("Created worktree at %s", wtPath))

		// Auto-add to config if enabled
		settings, _ := config.ParseSettings(config.SettingsFile())
		if settings.AutoAddClone {
			sName := sanitizeName(name)
			if err := config.AddProject(config.ProjectsFile(), sName, root); err != nil {
				ilog.Warn(fmt.Sprintf("Could not add to config: %s", err))
			} else {
				ilog.Info(fmt.Sprintf("Added '%s' to projects.conf", sName))
			}
		}

		return nil
	},
}

func detectDefaultBranch(root string) string {
	// Try symbolic ref
	out, err := exec.Command("git", "-C", root, "symbolic-ref",
		"refs/remotes/origin/HEAD", "--short").Output()
	if err == nil {
		branch := strings.TrimSpace(string(out))
		branch = strings.TrimPrefix(branch, "origin/")
		if branch != "" {
			return branch
		}
	}
	// Try main, then master
	for _, b := range []string{"main", "master"} {
		check := exec.Command("git", "-C", root, "rev-parse", "--verify", "refs/remotes/origin/"+b)
		if check.Run() == nil {
			return b
		}
	}
	// Fall back to first remote branch
	out, err = exec.Command("git", "-C", root, "branch", "-r", "--format=%(refname:short)").Output()
	if err == nil {
		for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "origin/") && !strings.Contains(line, "HEAD") {
				return strings.TrimPrefix(line, "origin/")
			}
		}
	}
	return "main"
}

func repoNameFromURL(url string) string {
	base := filepath.Base(url)
	return strings.TrimSuffix(base, ".git")
}
