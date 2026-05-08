package git

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Worktree represents a git worktree.
type Worktree struct {
	Path string
	Name string
}

// DepthRepo is a git repo discovered by depth scanning.
type DepthRepo struct {
	Path string
	Name string
}

// RepoInfo describes a git repository.
type RepoInfo struct {
	Root string
	Type string // "bare" or "normal"
}

// IsBareRepo returns true if path is a bare repo in the txs layout
// (.bare/ subdirectory) or a standard bare repository.
func IsBareRepo(path string) bool {
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

// ListWorktrees returns worktrees for the given repo path, skipping the bare entry.
func ListWorktrees(path string) ([]Worktree, error) {
	out, err := exec.Command("git", "-C", path, "worktree", "list", "--porcelain").Output()
	if err != nil {
		return nil, err
	}

	var worktrees []Worktree
	var currentPath string
	isBare := false

	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	flush := func() {
		if currentPath != "" && !isBare {
			worktrees = append(worktrees, Worktree{
				Path: currentPath,
				Name: filepath.Base(currentPath),
			})
		}
		currentPath = ""
		isBare = false
	}

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			flush()
			continue
		}
		if strings.HasPrefix(line, "worktree ") {
			currentPath = strings.TrimPrefix(line, "worktree ")
		} else if line == "bare" {
			isBare = true
		}
	}
	flush()
	return worktrees, nil
}

// ScanDepth recursively scans root up to maxDepth levels for git repos.
// It stops descending once a git repo is found in a subtree and skips hidden dirs.
func ScanDepth(root string, maxDepth int) ([]DepthRepo, error) {
	if maxDepth <= 0 {
		return nil, nil
	}
	var results []DepthRepo
	err := scanDir(root, maxDepth, 0, &results)
	return results, err
}

func scanDir(dir string, maxDepth, currentDepth int, results *[]DepthRepo) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil // skip unreadable dirs silently
	}

	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		name := e.Name()
		if strings.HasPrefix(name, ".") {
			continue // skip hidden
		}

		absPath := filepath.Join(dir, name)
		// Resolve symlinks
		resolved, err := filepath.EvalSymlinks(absPath)
		if err != nil {
			resolved = absPath
		}

		if ownsGitRepo(resolved) {
			*results = append(*results, DepthRepo{Path: resolved, Name: name})
			// Don't recurse into git repos
		} else if currentDepth+1 < maxDepth {
			scanDir(resolved, maxDepth, currentDepth+1, results)
		}
	}
	return nil
}

// ownsGitRepo returns true if the directory directly owns a git repo
// (not just inheriting one from a parent).
func ownsGitRepo(path string) bool {
	out, err := exec.Command("git", "-C", path, "rev-parse", "--git-dir").Output()
	if err != nil {
		return false
	}
	gitDir := strings.TrimSpace(string(out))
	if !filepath.IsAbs(gitDir) {
		gitDir = filepath.Join(path, gitDir)
	}
	resolved, err := filepath.EvalSymlinks(gitDir)
	if err != nil {
		resolved = gitDir
	}
	// The git dir must be inside (or be) the path itself
	return strings.HasPrefix(resolved, path+string(os.PathSeparator)) || resolved == path
}

// GetRepoInfo detects the repo root and type from a given directory.
func GetRepoInfo(cwd string) (RepoInfo, error) {
	// Check for bare layout (.bare/)
	commonDir, err := exec.Command("git", "-C", cwd, "rev-parse", "--git-common-dir").Output()
	if err != nil {
		return RepoInfo{}, fmt.Errorf("not inside a git repository")
	}
	commonDirStr := strings.TrimSpace(string(commonDir))
	if !filepath.IsAbs(commonDirStr) {
		commonDirStr = filepath.Join(cwd, commonDirStr)
	}
	if resolved, err := filepath.EvalSymlinks(commonDirStr); err == nil {
		commonDirStr = resolved
	}
	if filepath.Base(commonDirStr) == ".bare" {
		root := filepath.Dir(commonDirStr)
		return RepoInfo{Root: root, Type: "bare"}, nil
	}

	// Normal repo
	out, err := exec.Command("git", "-C", cwd, "rev-parse", "--show-toplevel").Output()
	if err != nil {
		return RepoInfo{}, fmt.Errorf("could not determine repository root")
	}
	root := strings.TrimSpace(string(out))
	if resolved, err := filepath.EvalSymlinks(root); err == nil {
		root = resolved
	}
	return RepoInfo{Root: root, Type: "normal"}, nil
}

// WorktreePath computes the directory where a worktree for branch should be created.
// For bare repos it is inside the repo; for normal repos it is a sibling.
func WorktreePath(root, repoName, branch string, bare bool) string {
	wtName := fmt.Sprintf("%s.%s", repoName, branch)
	if bare {
		return filepath.Join(root, wtName)
	}
	return filepath.Join(filepath.Dir(root), wtName)
}

// RepoNameFromURL derives a directory name from a git URL.
func RepoNameFromURL(url string) string {
	base := filepath.Base(url)
	base = strings.TrimSuffix(base, ".git")
	return base
}
