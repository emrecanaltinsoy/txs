package ui

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// Entry represents one line in the fzf picker.
type Entry struct {
	Marker      string // "*", " ", or "+"
	Session     string // "-" if none
	Project     string // project name or depth-parent name; "-" if none
	WtPath      string // worktree path; "-" if none
	DisplayPath string // full bare-repo path for depth entries
	Label       string // what fzf displays
}

func (e Entry) Encode() string {
	session := e.Session
	if session == "" {
		session = "-"
	}
	project := e.Project
	if project == "" {
		project = "-"
	}
	wtPath := e.WtPath
	if wtPath == "" {
		wtPath = "-"
	}
	displayPath := e.DisplayPath
	if displayPath == "" {
		displayPath = "-"
	}
	return fmt.Sprintf("%s\t%s\t%s\t%s\t%s\t%s", e.Marker, session, project, wtPath, displayPath, e.Label)
}

func DecodeEntry(line string) Entry {
	parts := strings.SplitN(line, "\t", 6)
	if len(parts) < 6 {
		return Entry{}
	}
	e := Entry{
		Marker:      parts[0],
		Session:     parts[1],
		Project:     parts[2],
		WtPath:      parts[3],
		DisplayPath: parts[4],
		Label:       parts[5],
	}
	if e.Session == "-" {
		e.Session = ""
	}
	if e.Project == "-" {
		e.Project = ""
	}
	if e.WtPath == "-" {
		e.WtPath = ""
	}
	if e.DisplayPath == "-" {
		e.DisplayPath = ""
	}
	return e
}

// FzfOpts configures fzf behaviour.
type FzfOpts struct {
	Header string
	Prompt string
	Height string
}

// RunFzf pipes entries to fzf and returns the selected Entry.
// Returns nil if the user cancelled (ESC / q).
func RunFzf(entries []Entry, opts FzfOpts) (*Entry, error) {
	if len(entries) == 0 {
		return nil, nil
	}

	height := opts.Height
	if height == "" {
		height = "50%"
	}

	args := []string{
		"--delimiter=\t",
		"--with-nth=6",
		"--header=" + opts.Header,
		"--prompt=" + opts.Prompt,
		"--height=" + height,
		"--layout=reverse",
		"--border",
		"--ansi",
	}

	cmd := exec.Command("fzf", args...)
	cmd.Stderr = os.Stderr

	var buf bytes.Buffer
	for _, e := range entries {
		buf.WriteString(e.Encode())
		buf.WriteByte('\n')
	}
	cmd.Stdin = &buf

	out, err := cmd.Output()
	if err != nil {
		// Exit code 130 = user cancelled
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 130 {
			return nil, nil
		}
		return nil, err
	}

	selected := strings.TrimRight(string(out), "\n")
	if selected == "" {
		return nil, nil
	}
	entry := DecodeEntry(selected)
	return &entry, nil
}
