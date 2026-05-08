package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/emrecanaltinsoy/txs/internal/config"
	ilog "github.com/emrecanaltinsoy/txs/internal/log"
	"github.com/emrecanaltinsoy/txs/internal/tmux"
	"github.com/emrecanaltinsoy/txs/internal/ui"
	"github.com/spf13/cobra"
)

var attachCmd = &cobra.Command{
	Use:   "attach [project] [worktree]",
	Short: "Attach to a project tmux session",
	Args:  cobra.MaximumNArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		if len(args) == 0 {
			return runInteractive()
		}
		projectName := args[0]
		wtSelector := ""
		if len(args) > 1 {
			wtSelector = args[1]
		}
		return attachProject(projectName, wtSelector)
	},
}

func attachProject(projectName, wtSelector string) error {
	projects, _, err := config.ParseProjects(config.ProjectsFile())
	if err != nil {
		return err
	}

	var proj *config.Project
	for i := range projects {
		if projects[i].Name == projectName {
			proj = &projects[i]
			break
		}
	}
	if proj == nil {
		ilog.Error(fmt.Sprintf("Project '%s' not found in config.", projectName))
		fmt.Fprintln(os.Stderr, "Available projects:")
		for _, p := range projects {
			fmt.Fprintf(os.Stderr, "  - %s\n", p.Name)
		}
		return fmt.Errorf("project not found")
	}

	if _, err := os.Stat(proj.Path); err != nil {
		return fmt.Errorf("directory does not exist: %s", proj.Path)
	}

	created, err := ensureSession(proj.SessionName, proj.Path, "")
	if err != nil {
		return err
	}
	if created && !isBareRepo(proj.Path) {
		sendOnCreateLines(proj.SessionName, proj.OnCreate)
	}

	if isBareRepo(proj.Path) {
		return attachBareRepo(proj, wtSelector)
	}
	return tmux.AttachOrSwitch(proj.SessionName)
}

func attachBareRepo(proj *config.Project, wtSelector string) error {
	wts, err := listWorktrees(proj.Path)
	if err != nil {
		return err
	}
	if len(wts) == 0 {
		return fmt.Errorf("no worktrees found in %s", proj.Path)
	}

	var target *wtEntry

	if wtSelector != "" {
		for i := range wts {
			if wts[i].Name == wtSelector {
				target = &wts[i]
				break
			}
		}
		if target == nil {
			return fmt.Errorf("worktree '%s' not found", wtSelector)
		}
	} else if len(wts) == 1 {
		target = &wts[0]
	} else {
		var entries []ui.Entry
		for _, wt := range wts {
			entries = append(entries, ui.Entry{
				Marker:  "+",
				Project: proj.Name,
				WtPath:  wt.Path,
				Label:   fmt.Sprintf("%s - %s", proj.Name, wt.Name),
			})
		}
		selected, err := ui.RunFzf(entries, ui.FzfOpts{
			Header: "Select worktree",
			Prompt: "worktree> ",
		})
		if err != nil || selected == nil {
			return nil
		}
		for i := range wts {
			if wts[i].Path == selected.WtPath {
				target = &wts[i]
				break
			}
		}
	}

	if target == nil {
		return nil
	}

	winIdx, _ := tmux.FindWindowByPath(proj.SessionName, target.Path)
	if winIdx != "" {
		return tmux.AttachOrSwitchWindow(proj.SessionName, winIdx)
	}

	newWin, err := tmuxNewWindow(proj.SessionName, target.Path)
	if err != nil {
		return err
	}
	sendOnCreateLines(proj.SessionName, proj.OnCreate)
	return tmux.AttachOrSwitchWindow(proj.SessionName, newWin)
}

func tmuxNewWindow(session, path string) (string, error) {
	out, err := exec.Command("tmux", "new-window", "-t", "="+session,
		"-c", path, "-P", "-F", "#{window_index}").Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}
