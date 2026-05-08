package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/emrecanaltinsoy/txs/internal/config"
	ilog "github.com/emrecanaltinsoy/txs/internal/log"
	"github.com/emrecanaltinsoy/txs/internal/tmux"
	"github.com/emrecanaltinsoy/txs/internal/ui"
	"github.com/spf13/cobra"
)

// runInteractive is the default action when txs is called without arguments.
// It presents a combined fzf picker of active sessions and inactive projects.
func runInteractive() error {
	if err := requireFzf(); err != nil {
		return err
	}

	projects, _, err := config.ParseProjects(config.ProjectsFile())
	if err != nil {
		return err
	}

	settings, _ := config.ParseSettings(config.SettingsFile())

	sessions, _ := tmux.ListSessions()
	activeSet := map[string]bool{}
	for _, s := range sessions {
		activeSet[s] = true
	}
	winMap, _ := tmux.SessionWindowSummary()

	// Build explicit path set for dedup
	explicitPaths := map[string]string{}
	for _, p := range projects {
		if p.MaxDepth == 0 {
			explicitPaths[p.Path] = p.Name
		}
	}

	// Pre-pass: depth project ownership (last wins)
	type depthEntry struct {
		project string
		path    string
	}
	depthByName := map[string]depthEntry{}
	for _, p := range projects {
		if p.MaxDepth <= 0 {
			continue
		}
		repos, _ := scanDepthDedup(p.Path, p.MaxDepth, explicitPaths)
		for _, r := range repos {
			depthByName[r.Name] = depthEntry{project: p.Name, path: r.Path}
		}
	}

	// session name → project (non-depth)
	sessionToProject := map[string]string{}
	for _, p := range projects {
		if p.MaxDepth == 0 {
			sessionToProject[p.SessionName] = p.Name
		}
	}

	var entries []ui.Entry
	seenProjects := map[string]bool{}
	seenDepthSessions := map[string]bool{}

	// --- Active sessions ---
	for _, sess := range sessions {
		projName := sessionToProject[sess]
		depthInfo, isDepth := depthByName[sess]

		if projName == "" && isDepth {
			// Depth-discovered active session
			seenDepthSessions[sess] = true
			dp := depthInfo.path
			if dp != "" {
				if isBareRepo(dp) {
					wts, _ := listWorktrees(dp)
					for _, wt := range wts {
						winIdx, _ := tmux.FindWindowByPath(sess, wt.Path)
						marker := " "
						if winIdx != "" {
							marker = "*"
						}
						label := fmt.Sprintf("%s %-20s %s", marker,
							fmt.Sprintf("[%s] %s - %s", depthInfo.project, sess, wt.Name),
							"[active]")
						entries = append(entries, ui.Entry{
							Marker:      marker,
							Session:     sess,
							Project:     depthInfo.project,
							WtPath:      wt.Path,
							DisplayPath: dp,
							Label:       label,
						})
					}
				} else {
					wins := winMap[sess]
					label := fmt.Sprintf("* %-20s [%s]",
						fmt.Sprintf("[%s] %s", depthInfo.project, sess), wins)
					entries = append(entries, ui.Entry{
						Marker:      "*",
						Session:     sess,
						Project:     depthInfo.project,
						DisplayPath: dp,
						Label:       label,
					})
				}
			}
			continue
		}

		if projName != "" {
			seenProjects[projName] = true
			for _, p := range projects {
				if p.Name != projName {
					continue
				}
				if isBareRepo(p.Path) {
					wts, _ := listWorktrees(p.Path)
					for _, wt := range wts {
						winIdx, _ := tmux.FindWindowByPath(sess, wt.Path)
						marker := " "
						if winIdx != "" {
							marker = "*"
						}
						label := fmt.Sprintf("%s %-20s %s", marker,
							fmt.Sprintf("%s - %s", projName, wt.Name), "[active]")
						entries = append(entries, ui.Entry{
							Marker:  marker,
							Session: sess,
							Project: projName,
							WtPath:  wt.Path,
							Label:   label,
						})
					}
					continue
				}
				wins := winMap[sess]
				label := fmt.Sprintf("* %-20s [%s]", projName, wins)
				entries = append(entries, ui.Entry{
					Marker:  "*",
					Session: sess,
					Project: projName,
					Label:   label,
				})
			}
		} else {
			// Unknown / non-configured session
			wins := winMap[sess]
			label := fmt.Sprintf("* %-20s [%s]", sess, wins)
			entries = append(entries, ui.Entry{
				Marker:  "*",
				Session: sess,
				Label:   label,
			})
		}
	}

	// --- Inactive projects ---
	for _, p := range projects {
		if p.MaxDepth > 0 {
			repos, _ := scanDepthDedup(p.Path, p.MaxDepth, explicitPaths)
			for _, r := range repos {
				if seenDepthSessions[r.Name] {
					continue
				}
				owner, ok := depthByName[r.Name]
				if !ok || owner.project != p.Name {
					continue
				}
				if isBareRepo(r.Path) {
					wts, _ := listWorktrees(r.Path)
					for _, wt := range wts {
						label := fmt.Sprintf("+ [%s] %s - %s", p.Name, r.Name, wt.Name)
						entries = append(entries, ui.Entry{
							Marker:      "+",
							Project:     p.Name,
							WtPath:      wt.Path,
							DisplayPath: r.Path,
							Label:       label,
						})
					}
				} else {
					label := fmt.Sprintf("+ [%s] %s", p.Name, r.Name)
					entries = append(entries, ui.Entry{
						Marker:      "+",
						Project:     p.Name,
						WtPath:      r.Path,
						DisplayPath: r.Path,
						Label:       label,
					})
				}
			}
			continue
		}

		if seenProjects[p.Name] {
			continue
		}
		if _, err := os.Stat(p.Path); err != nil {
			continue
		}
		if isBareRepo(p.Path) {
			wts, _ := listWorktrees(p.Path)
			for _, wt := range wts {
				label := fmt.Sprintf("+ %s - %s", p.Name, wt.Name)
				entries = append(entries, ui.Entry{
					Marker:  "+",
					Project: p.Name,
					WtPath:  wt.Path,
					Label:   label,
				})
			}
		} else {
			label := fmt.Sprintf("+ %s", p.Name)
			entries = append(entries, ui.Entry{
				Marker:  "+",
				Project: p.Name,
				Label:   label,
			})
		}
	}

	if len(entries) == 0 {
		fmt.Println(ilog.Dim("No sessions or projects available."))
		return nil
	}

	selected, err := ui.RunFzf(entries, ui.FzfOpts{
		Header: "* = active  + = project | ESC to cancel",
		Prompt: "session> ",
		Height: settings.FzfHeight,
	})
	if err != nil || selected == nil {
		return nil
	}

	return handleInteractiveSelection(selected, projects)
}

func handleInteractiveSelection(sel *ui.Entry, projects []config.Project) error {
	switch sel.Marker {
	case "*":
		if sel.WtPath != "" && sel.Session != "" {
			return openWorktreeInSession(sel.Session, sel.WtPath)
		}
		return tmux.AttachOrSwitch(sel.Session)

	case " ":
		if sel.WtPath != "" && sel.Session != "" {
			return openWorktreeInSession(sel.Session, sel.WtPath)
		}

	case "+":
		// Depth-discovered entry with a direct path
		if sel.DisplayPath != "" && sel.WtPath != "" {
			// Bare worktree under a depth project
			if isBareRepo(sel.DisplayPath) {
				sessName := tmux.SanitizeName(lastPathComponent(sel.DisplayPath))
				proj := findProjectByName(projects, sel.Project)
				onCreateLines := []string{}
				if proj != nil {
					onCreateLines = proj.OnCreate
				}
				created, err := ensureSession(sessName, sel.DisplayPath, "")
				if err != nil {
					return err
				}
				if created {
					sendOnCreateLines(sessName, onCreateLines)
				}
				return openWorktreeInSession(sessName, sel.WtPath)
			}
			// Non-bare depth-discovered repo
			sessName := tmux.SanitizeName(lastPathComponent(sel.WtPath))
			proj := findProjectByName(projects, sel.Project)
			onCreateLines := []string{}
			if proj != nil {
				onCreateLines = proj.OnCreate
			}
			created, err := ensureSession(sessName, sel.WtPath, "")
			if err != nil {
				return err
			}
			if created {
				sendOnCreateLines(sessName, onCreateLines)
			}
			return tmux.AttachOrSwitch(sessName)
		}
		// Explicit project (bare worktree)
		if sel.WtPath != "" && sel.Project != "" {
			proj := findProjectByName(projects, sel.Project)
			if proj == nil {
				return fmt.Errorf("project not found: %s", sel.Project)
			}
			// Is this a bare repo worktree?
			if isBareRepo(proj.Path) {
				return attachBareRepo(proj, lastPathComponent(sel.WtPath))
			}
		}
		// Plain inactive project
		if sel.Project != "" {
			return attachProject(sel.Project, "")
		}
	}
	return nil
}

func findProjectByName(projects []config.Project, name string) *config.Project {
	for i := range projects {
		if projects[i].Name == name {
			return &projects[i]
		}
	}
	return nil
}

func openWorktreeInSession(session, wtPath string) error {
	winIdx, _ := tmux.FindWindowByPath(session, wtPath)
	if winIdx != "" {
		return tmux.AttachOrSwitchWindow(session, winIdx)
	}
	newWin, err := tmuxNewWindow(session, wtPath)
	if err != nil {
		return err
	}
	return tmux.AttachOrSwitchWindow(session, newWin)
}

// switchCmd shows only active sessions.
var switchCmd = &cobra.Command{
	Use:   "switch",
	Short: "Switch between active tmux sessions",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runSwitch()
	},
}

func runSwitch() error {
	if err := requireFzf(); err != nil {
		return err
	}

	sessions, _ := tmux.ListSessions()
	if len(sessions) == 0 {
		return fmt.Errorf("no active tmux sessions")
	}

	projects, _, _ := config.ParseProjects(config.ProjectsFile())
	settings, _ := config.ParseSettings(config.SettingsFile())
	winMap, _ := tmux.SessionWindowSummary()

	explicitPaths := map[string]string{}
	for _, p := range projects {
		if p.MaxDepth == 0 {
			explicitPaths[p.Path] = p.Name
		}
	}
	type depthEntry struct {
		project string
		path    string
	}
	depthByName := map[string]depthEntry{}
	for _, p := range projects {
		if p.MaxDepth <= 0 {
			continue
		}
		repos, _ := scanDepthDedup(p.Path, p.MaxDepth, explicitPaths)
		for _, r := range repos {
			depthByName[r.Name] = depthEntry{project: p.Name, path: r.Path}
		}
	}
	sessionToProject := map[string]string{}
	for _, p := range projects {
		if p.MaxDepth == 0 {
			sessionToProject[p.SessionName] = p.Name
		}
	}

	var entries []ui.Entry
	for _, sess := range sessions {
		projName := sessionToProject[sess]
		depthInfo, isDepth := depthByName[sess]

		if projName == "" && isDepth {
			dp := depthInfo.path
			if dp != "" && isBareRepo(dp) {
				wts, _ := listWorktrees(dp)
				for _, wt := range wts {
					winIdx, _ := tmux.FindWindowByPath(sess, wt.Path)
					if winIdx == "" {
						continue
					}
					label := fmt.Sprintf("* %-20s %s",
						fmt.Sprintf("[%s] %s - %s", depthInfo.project, sess, wt.Name),
						"[active]")
					entries = append(entries, ui.Entry{
						Marker:      "*",
						Session:     sess,
						Project:     depthInfo.project,
						WtPath:      wt.Path,
						DisplayPath: dp,
						Label:       label,
					})
				}
			} else {
				wins := winMap[sess]
				label := fmt.Sprintf("* %-20s [%s]",
					fmt.Sprintf("[%s] %s", depthInfo.project, sess), wins)
				entries = append(entries, ui.Entry{
					Marker:  "*",
					Session: sess,
					Project: depthInfo.project,
					Label:   label,
				})
			}
			continue
		}

		if projName != "" {
			for _, p := range projects {
				if p.Name != projName {
					continue
				}
				if isBareRepo(p.Path) {
					wts, _ := listWorktrees(p.Path)
					for _, wt := range wts {
						winIdx, _ := tmux.FindWindowByPath(sess, wt.Path)
						if winIdx == "" {
							continue
						}
						label := fmt.Sprintf("* %-20s %s",
							fmt.Sprintf("%s - %s", projName, wt.Name), "[active]")
						entries = append(entries, ui.Entry{
							Marker:  "*",
							Session: sess,
							Project: projName,
							WtPath:  wt.Path,
							Label:   label,
						})
					}
					continue
				}
				wins := winMap[sess]
				label := fmt.Sprintf("* %-20s [%s]", projName, wins)
				entries = append(entries, ui.Entry{
					Marker:  "*",
					Session: sess,
					Project: projName,
					Label:   label,
				})
			}
		} else {
			wins := winMap[sess]
			label := fmt.Sprintf("* %-20s [%s]", sess, wins)
			entries = append(entries, ui.Entry{
				Marker:  "*",
				Session: sess,
				Label:   label,
			})
		}
	}

	if len(entries) == 0 {
		fmt.Println(ilog.Dim("No active sessions."))
		return nil
	}

	selected, err := ui.RunFzf(entries, ui.FzfOpts{
		Header: "Active sessions | ESC to cancel",
		Prompt: "switch> ",
		Height: settings.FzfHeight,
	})
	if err != nil || selected == nil {
		return nil
	}

	if selected.WtPath != "" && selected.Session != "" {
		return openWorktreeInSession(selected.Session, selected.WtPath)
	}
	if selected.Session != "" {
		return tmux.AttachOrSwitch(selected.Session)
	}
	return nil
}

// stripPrefix removes a "reponame." prefix from a worktree display name.
func stripPrefix(name, prefix string) string {
	p := prefix + "."
	if strings.HasPrefix(name, p) {
		return name[len(p):]
	}
	return name
}
