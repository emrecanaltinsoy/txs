package cmd

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"

	ilog "github.com/emrecanaltinsoy/txs/internal/log"
	"github.com/spf13/cobra"
)

var wtCmd = &cobra.Command{
	Use:   "wt [add|remove|list]",
	Short: "Manage git worktrees",
	Args:  cobra.MaximumNArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		sub := "list"
		if len(args) > 0 {
			sub = args[0]
		}
		rest := args[1:]
		switch sub {
		case "add":
			branch := ""
			if len(rest) > 0 {
				branch = rest[0]
			}
			return wtAdd(branch)
		case "remove", "rm":
			branch := ""
			keepBranch := false
			for _, a := range rest {
				if a == "--keep-branch" || a == "-k" {
					keepBranch = true
				} else {
					branch = a
				}
			}
			return wtRemove(branch, keepBranch)
		case "list", "ls":
			return wtList()
		default:
			return fmt.Errorf("Unknown wt subcommand '%s'. Use: add, remove, list", sub)
		}
	},
}

func getRepoInfo() (root, repoType string, err error) {
	cwd, err := os.Getwd()
	if err != nil {
		return "", "", err
	}
	// Check for .bare layout
	commonDir, err2 := exec.Command("git", "-C", cwd, "rev-parse", "--git-common-dir").Output()
	if err2 != nil {
		return "", "", fmt.Errorf("Not inside a git repository")
	}
	commonDirStr := strings.TrimSpace(string(commonDir))
	if !strings.HasPrefix(commonDirStr, "/") {
		commonDirStr = cwd + "/" + commonDirStr
	}
	if base := lastPathComponent(commonDirStr); base == ".bare" {
		return parentDir(commonDirStr), "bare", nil
	}
	out, err2 := exec.Command("git", "-C", cwd, "rev-parse", "--show-toplevel").Output()
	if err2 != nil {
		return "", "", fmt.Errorf("could not determine repository root")
	}
	return strings.TrimSpace(string(out)), "normal", nil
}

func lastPathComponent(path string) string {
	parts := strings.Split(strings.TrimSuffix(path, "/"), "/")
	if len(parts) == 0 {
		return ""
	}
	return parts[len(parts)-1]
}

func parentDir(path string) string {
	parts := strings.Split(strings.TrimSuffix(path, "/"), "/")
	if len(parts) <= 1 {
		return "/"
	}
	return strings.Join(parts[:len(parts)-1], "/")
}

func wtAdd(branch string) error {
	root, repoType, err := getRepoInfo()
	if err != nil {
		return err
	}

	if branch == "" {
		fmt.Print("Branch name: ")
		scanner := bufio.NewScanner(os.Stdin)
		if !scanner.Scan() {
			return fmt.Errorf("Missing branch name")
		}
		branch = strings.TrimSpace(scanner.Text())
		if branch == "" {
			return fmt.Errorf("Missing branch name")
		}
	}

	repoName := lastPathComponent(root)
	bare := repoType == "bare"
	wtPath := worktreePath(root, repoName, branch, bare)

	// Determine if remote branch exists
	remoteRef := "refs/remotes/origin/" + branch
	localRef := "refs/heads/" + branch
	remoteExists := exec.Command("git", "-C", root, "rev-parse", "--verify", remoteRef).Run() == nil
	localExists := exec.Command("git", "-C", root, "rev-parse", "--verify", localRef).Run() == nil

	var wtArgs []string
	if remoteExists && localExists {
		wtArgs = []string{"worktree", "add", wtPath, branch}
	} else if remoteExists {
		wtArgs = []string{"worktree", "add", "--track", "-b", branch, wtPath, "origin/" + branch}
	} else {
		wtArgs = []string{"worktree", "add", "-b", branch, wtPath, "HEAD"}
	}

	cmd := exec.Command("git", append([]string{"-C", root}, wtArgs...)...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to create worktree: %w", err)
	}
	ilog.Info(fmt.Sprintf("Created worktree at %s", wtPath))
	return nil
}

func wtRemove(branch string, keepBranch bool) error {
	root, repoType, err := getRepoInfo()
	if err != nil {
		return err
	}
	bare := repoType == "bare"

	if branch == "" {
		wts, err := listWorktrees(root)
		if err != nil {
			return err
		}
		// Filter out the main worktree (repoName.default branch pattern is ambiguous;
		// show all and let user pick)
		entries := make([]string, 0, len(wts))
		for _, wt := range wts {
			entries = append(entries, wt.Name)
		}
		if len(entries) == 0 {
			return fmt.Errorf("no worktrees found")
		}
		fmt.Print("Branch to remove: ")
		scanner := bufio.NewScanner(os.Stdin)
		if !scanner.Scan() {
			return fmt.Errorf("Missing branch name")
		}
		branch = strings.TrimSpace(scanner.Text())
		if branch == "" {
			return fmt.Errorf("Missing branch name")
		}
	}

	repoName := lastPathComponent(root)
	wtPath := worktreePath(root, repoName, branch, bare)

	rmCmd := exec.Command("git", "-C", root, "worktree", "remove", wtPath)
	rmCmd.Stdout = os.Stdout
	rmCmd.Stderr = os.Stderr
	if err := rmCmd.Run(); err != nil {
		return fmt.Errorf("failed to remove worktree: %w", err)
	}

	if !keepBranch {
		_ = exec.Command("git", "-C", root, "branch", "-d", branch).Run()
	}
	ilog.Info(fmt.Sprintf("Removed worktree for branch '%s'", branch))
	return nil
}

func wtList() error {
	root, _, err := getRepoInfo()
	if err != nil {
		return err
	}
	wts, err := listWorktrees(root)
	if err != nil {
		return err
	}
	if len(wts) == 0 {
		fmt.Println(ilog.Dim("No worktrees found."))
		return nil
	}
	fmt.Println(ilog.Bold("Worktrees:"))
	fmt.Println()
	for _, wt := range wts {
		fmt.Printf("  %s  %s\n", ilog.Cyan(wt.Name), ilog.Dim(wt.Path))
	}
	return nil
}

func worktreePath(root, repoName, branch string, bare bool) string {
	wtName := repoName + "." + branch
	if bare {
		return root + "/" + wtName
	}
	return parentDir(root) + "/" + wtName
}
