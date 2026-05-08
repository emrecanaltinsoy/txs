package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/emrecanaltinsoy/txs/internal/tmux"
	ilog "github.com/emrecanaltinsoy/txs/internal/log"
	"github.com/emrecanaltinsoy/txs/internal/ui"
	"github.com/spf13/cobra"
)

var killCmd = &cobra.Command{
	Use:   "kill [session|window]",
	Short: "Kill a tmux session or window",
	Args:  cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		if len(args) == 1 && args[0] == "window" {
			return killWindow()
		}
		if len(args) == 1 {
			return killSession(args[0])
		}
		return killSessionInteractive()
	},
}

func currentSessionName() string {
	if !tmux.IsInsideTmux() {
		return ""
	}
	out, err := exec.Command("tmux", "display-message", "-p", "#{session_name}").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func killSession(name string) error {
	sessions, _ := tmux.ListSessions()
	current := currentSessionName()

	if current == name && len(sessions) > 1 {
		for _, s := range sessions {
			if s != name {
				_ = tmux.AttachOrSwitch(s)
				break
			}
		}
	}
	if err := tmux.KillSession(name); err != nil {
		return fmt.Errorf("failed to kill session '%s': %w", name, err)
	}
	ilog.Info(fmt.Sprintf("Killed session '%s'", name))
	return nil
}

func killSessionInteractive() error {
	sessions, _ := tmux.ListSessions()
	if len(sessions) == 0 {
		fmt.Println(ilog.Dim("No active tmux sessions."))
		return nil
	}
	winMap, _ := tmux.SessionWindowSummary()
	var entries []ui.Entry
	for _, s := range sessions {
		wins := winMap[s]
		entries = append(entries, ui.Entry{
			Marker:  "*",
			Session: s,
			Label:   fmt.Sprintf("%-20s [%s]", s, wins),
		})
	}
	selected, err := ui.RunFzf(entries, ui.FzfOpts{
		Header: "Select session to kill",
		Prompt: "kill> ",
	})
	if err != nil || selected == nil {
		return nil
	}
	return killSession(selected.Session)
}

func killWindow() error {
	sessions, _ := tmux.ListSessions()
	if len(sessions) == 0 {
		fmt.Println(ilog.Dim("No active tmux sessions."))
		return nil
	}
	var entries []ui.Entry
	for _, s := range sessions {
		wins, err := tmux.ListWindows(s)
		if err != nil {
			continue
		}
		for _, w := range wins {
			entries = append(entries, ui.Entry{
				Marker:  "*",
				Session: s,
				Project: w.Index, // reuse Project field for window index
				Label:   fmt.Sprintf("%-20s %s", s, w.Name),
			})
		}
	}
	if len(entries) == 0 {
		fmt.Println(ilog.Dim("No windows found."))
		return nil
	}
	selected, err := ui.RunFzf(entries, ui.FzfOpts{
		Header: "Select window to kill",
		Prompt: "kill window> ",
	})
	if err != nil || selected == nil {
		return nil
	}
	if err := tmux.KillWindow(selected.Session, selected.Project); err != nil {
		return fmt.Errorf("failed to kill window: %w", err)
	}
	ilog.Info(fmt.Sprintf("Killed window %s in session '%s'", selected.Project, selected.Session))
	return nil
}

// execOutput runs a command and returns trimmed stdout.
func execOutput(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).Output()
	return strings.TrimSpace(string(out)), err
}

// requireTmux returns an error if tmux is not available.
func requireTmux() error {
	if _, err := exec.LookPath("tmux"); err != nil {
		return fmt.Errorf("tmux is required but not found in PATH")
	}
	return nil
}

// requireFzf returns an error if fzf is not available.
func requireFzf() error {
	if _, err := exec.LookPath("fzf"); err != nil {
		return fmt.Errorf("fzf is required for interactive mode")
	}
	return nil
}

// openEditor opens a file in $EDITOR.
func openEditor(path string) error {
	editor := os.Getenv("EDITOR")
	if editor == "" {
		editor = "vi"
	}
	cmd := exec.Command(editor, path)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
