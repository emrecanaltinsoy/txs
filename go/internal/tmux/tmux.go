package tmux

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// IsInsideTmux returns true if the process is running inside a tmux session.
func IsInsideTmux() bool {
	return os.Getenv("TMUX") != ""
}

// SanitizeName replaces characters tmux substitutes (. and :) with _.
func SanitizeName(s string) string {
	r := strings.NewReplacer(".", "_", ":", "_")
	return r.Replace(s)
}

// SessionExists returns true if a tmux session with the given name exists.
func SessionExists(name string) bool {
	err := exec.Command("tmux", "has-session", "-t", "="+name).Run()
	return err == nil
}

// NewSession creates a new detached tmux session at the given path.
func NewSession(name, path string) error {
	cmd := exec.Command("tmux", "new-session", "-d", "-s", name, "-c", path)
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// AttachOrSwitch attaches to (outside tmux) or switches to (inside tmux) a session.
func AttachOrSwitch(name string) error {
	if IsInsideTmux() {
		return exec.Command("tmux", "switch-client", "-t", "="+name).Run()
	}
	cmd := exec.Command("tmux", "attach-session", "-t", "="+name)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// AttachOrSwitchWindow switches to a specific session:window.
func AttachOrSwitchWindow(session, window string) error {
	target := fmt.Sprintf("%s:%s", session, window)
	if IsInsideTmux() {
		return exec.Command("tmux", "switch-client", "-t", target).Run()
	}
	// Find a client TTY if not inside tmux
	out, err := exec.Command("tmux", "list-clients", "-F", "#{client_tty}").Output()
	if err != nil || len(strings.TrimSpace(string(out))) == 0 {
		cmd := exec.Command("tmux", "attach-session", "-t", "="+session)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return cmd.Run()
	}
	tty := strings.SplitN(strings.TrimSpace(string(out)), "\n", 2)[0]
	return exec.Command("tmux", "switch-client", "-c", tty, "-t", target).Run()
}

// ListSessions returns the names of all active tmux sessions.
func ListSessions() ([]string, error) {
	out, err := exec.Command("tmux", "list-sessions", "-F", "#{session_name}").Output()
	if err != nil {
		return nil, nil // no sessions running
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	result := []string{}
	for _, l := range lines {
		if l != "" {
			result = append(result, l)
		}
	}
	return result, nil
}

// KillSession kills a named tmux session.
func KillSession(name string) error {
	return exec.Command("tmux", "kill-session", "-t", "="+name).Run()
}

// Window represents a tmux window.
type Window struct {
	Index string
	Name  string
}

// ListWindows returns the windows of a session.
func ListWindows(session string) ([]Window, error) {
	out, err := exec.Command("tmux", "list-windows", "-t", "="+session,
		"-F", "#{window_index}:#{window_name}").Output()
	if err != nil {
		return nil, err
	}
	var windows []Window
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 {
			windows = append(windows, Window{Index: parts[0], Name: parts[1]})
		}
	}
	return windows, nil
}

// KillWindow kills a specific window in a session.
func KillWindow(session, windowIndex string) error {
	target := fmt.Sprintf("%s:%s", session, windowIndex)
	return exec.Command("tmux", "kill-window", "-t", target).Run()
}

// SendKeys sends keystrokes to a session (to the active pane).
func SendKeys(session, keys string) error {
	return exec.Command("tmux", "send-keys", "-t", "="+session, keys, "Enter").Run()
}

// Pane represents a tmux pane with its session and current path.
type Pane struct {
	Session string
	Path    string
}

// ListPanes returns all panes across all sessions with their paths.
func ListPanes() ([]Pane, error) {
	out, err := exec.Command("tmux", "list-panes", "-a",
		"-F", "#{session_name}|#{pane_current_path}").Output()
	if err != nil {
		return nil, nil
	}
	var panes []Pane
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "|", 2)
		if len(parts) == 2 {
			panes = append(panes, Pane{Session: parts[0], Path: parts[1]})
		}
	}
	return panes, nil
}

// FindWindowByPath finds the window index in a session whose pane path matches
// the given worktree path.
func FindWindowByPath(session, path string) (string, error) {
	out, err := exec.Command("tmux", "list-windows", "-t", "="+session,
		"-F", "#{window_index}").Output()
	if err != nil {
		return "", err
	}
	for _, idx := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if idx == "" {
			continue
		}
		target := fmt.Sprintf("%s:%s", session, idx)
		paneOut, err := exec.Command("tmux", "list-panes", "-t", target,
			"-F", "#{pane_current_path}").Output()
		if err != nil {
			continue
		}
		for _, panePath := range strings.Split(strings.TrimSpace(string(paneOut)), "\n") {
			if panePath == path {
				return idx, nil
			}
		}
	}
	return "", nil
}

// SessionWindowSummary returns a map of session name → comma-separated window names.
func SessionWindowSummary() (map[string]string, error) {
	out, err := exec.Command("tmux", "list-windows", "-a",
		"-F", "#{session_name}:#{window_name}").Output()
	if err != nil {
		return nil, nil
	}
	result := map[string]string{}
	windowLists := map[string][]string{}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 {
			windowLists[parts[0]] = append(windowLists[parts[0]], parts[1])
		}
	}
	for sess, wins := range windowLists {
		result[sess] = strings.Join(wins, ",")
	}
	return result, nil
}
