package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/emrecanaltinsoy/txs/internal/config"
	ilog "github.com/emrecanaltinsoy/txs/internal/log"
	"github.com/emrecanaltinsoy/txs/internal/tmux"
	"github.com/spf13/cobra"
)

var lsCmd = &cobra.Command{
	Use:       "ls [sessions|projects|worktrees]",
	Short:     "List sessions, projects, or worktrees",
	Args:      cobra.MaximumNArgs(1),
	ValidArgs: []string{"sessions", "projects", "worktrees"},
	RunE: func(cmd *cobra.Command, args []string) error {
		filter := ""
		if len(args) > 0 {
			filter = args[0]
		}
		switch filter {
		case "", "sessions":
			if err := lsSessions(); err != nil {
				return err
			}
			if filter != "" {
				return nil
			}
			fmt.Println()
			fallthrough
		case "projects":
			if err := lsProjects(); err != nil {
				return err
			}
			if filter != "" {
				return nil
			}
			fmt.Println()
			fallthrough
		case "worktrees":
			return lsWorktrees()
		default:
			return fmt.Errorf("unknown filter '%s'. Use: sessions, projects, worktrees", filter)
		}
	},
}

// aliases
var listCmd = &cobra.Command{
	Use:    "list",
	Short:  "Alias for ls",
	Hidden: true,
	RunE:   lsCmd.RunE,
}
var sessionsCmd = &cobra.Command{
	Use:    "sessions",
	Short:  "Alias for ls sessions",
	Hidden: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		return lsSessions()
	},
}
var projectsCmd = &cobra.Command{
	Use:    "projects",
	Short:  "Alias for ls projects",
	Hidden: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		return lsProjects()
	},
}

func lsSessions() error {
	sessions, err := tmux.ListSessions()
	if err != nil {
		return err
	}
	fmt.Println(ilog.Bold("Active sessions:"))
	fmt.Println()
	if len(sessions) == 0 {
		fmt.Println(ilog.Dim("  No active tmux sessions."))
		return nil
	}
	winMap, _ := tmux.SessionWindowSummary()
	for _, s := range sessions {
		wins := winMap[s]
		fmt.Printf("  %s  %s\n", ilog.Cyan(s), ilog.Dim("["+wins+"]"))
	}
	return nil
}

func lsProjects() error {
	projects, _, err := config.ParseProjects(config.ProjectsFile())
	if err != nil {
		return err
	}
	if len(projects) == 0 {
		fmt.Println(ilog.Dim("No projects configured in " + config.ProjectsFile()))
		return nil
	}

	sessions, _ := tmux.ListSessions()
	activeSet := map[string]bool{}
	for _, s := range sessions {
		activeSet[s] = true
	}

	fmt.Println(ilog.Bold("Configured projects:"))
	fmt.Println()

	// Build set of explicit (non-depth) project paths for dedup
	explicitPaths := map[string]string{}
	for _, p := range projects {
		if p.MaxDepth == 0 {
			explicitPaths[p.Path] = p.Name
		}
	}

	// Pre-pass: for depth projects, record owner basename → project (last wins)
	type depthOwner struct {
		project string
	}
	depthOwners := map[string]depthOwner{} // basename → owner project name
	for _, p := range projects {
		if p.MaxDepth <= 0 {
			continue
		}
		repos, _ := scanDepthDedup(p.Path, p.MaxDepth, explicitPaths)
		for _, r := range repos {
			depthOwners[r.Name] = depthOwner{project: p.Name}
		}
	}

	for _, p := range projects {
		if p.MaxDepth > 0 {
			fmt.Printf("  %s  %s  %s\n",
				ilog.Cyan(p.Name),
				ilog.Dim(fmt.Sprintf("[depth=%d]", p.MaxDepth)),
				p.Path,
			)
			repos, _ := scanDepthDedup(p.Path, p.MaxDepth, explicitPaths)
			for _, r := range repos {
				// Only emit if this project is the owner
				if owner, ok := depthOwners[r.Name]; !ok || owner.project != p.Name {
					continue
				}
				status := ilog.Dim("inactive")
				if activeSet[r.Name] {
					status = ilog.Green("active")
				}
				fmt.Printf("    %s  [%s]  %s\n", r.Name, status, r.Path)
			}
			continue
		}
		if _, err := os.Stat(p.Path); err != nil {
			continue // skip non-existent dirs
		}
		status := ilog.Dim("inactive")
		if activeSet[p.SessionName] {
			status = ilog.Green("active")
		}
		fmt.Printf("  %s  [%s]  %s\n", ilog.Cyan(p.Name), status, p.Path)
	}
	return nil
}

func lsWorktrees() error {
	projects, _, err := config.ParseProjects(config.ProjectsFile())
	if err != nil {
		return err
	}

	found := false
	for _, p := range projects {
		if _, err := os.Stat(p.Path); err != nil {
			continue
		}
		if !isBareRepo(p.Path) {
			continue
		}
		wts, err := listWorktrees(p.Path)
		if err != nil {
			continue
		}
		if len(wts) == 0 {
			continue
		}
		if !found {
			fmt.Println(ilog.Bold("Worktrees:"))
			fmt.Println()
			found = true
		}
		// Sort by name
		sort.Slice(wts, func(i, j int) bool { return wts[i].Name < wts[j].Name })
		for _, wt := range wts {
			fmt.Printf("  %s - %s  %s\n", ilog.Cyan(p.Name), wt.Name, ilog.Dim(wt.Path))
		}
	}
	if !found {
		fmt.Println(ilog.Dim("No worktrees found."))
	}
	return nil
}

// scanDepthDedup runs a depth scan and filters out paths matching explicit projects.
type repo struct{ Path, Name string }

func scanDepthDedup(root string, maxDepth int, explicitPaths map[string]string) ([]repo, error) {
	var results []repo

	var scan func(dir string, depth int)
	scan = func(dir string, depth int) {
		entries, err := os.ReadDir(dir)
		if err != nil {
			return
		}
		for _, e := range entries {
			if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
				continue
			}
			abs := filepath.Join(dir, e.Name())
			if resolved, err := filepath.EvalSymlinks(abs); err == nil {
				abs = resolved
			}
			if _, skip := explicitPaths[abs]; skip {
				continue
			}
			if ownsGitDir(abs) {
				results = append(results, repo{Path: abs, Name: e.Name()})
			} else if depth+1 < maxDepth {
				scan(abs, depth+1)
			}
		}
	}
	scan(root, 0)
	return results, nil
}
