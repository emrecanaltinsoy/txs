package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/emrecanaltinsoy/txs/internal/config"
	ilog "github.com/emrecanaltinsoy/txs/internal/log"
	"github.com/spf13/cobra"
)

var addCmd = &cobra.Command{
	Use:   "add [path]",
	Short: "Add a directory to projects.conf",
	Args:  cobra.MaximumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		dir := "."
		if len(args) > 0 {
			dir = args[0]
		}

		absPath, err := realpath(dir)
		if err != nil {
			return fmt.Errorf("path does not exist: %s", dir)
		}

		// Derive section name from basename, sanitizing invalid chars
		name := sanitizeName(strings.ReplaceAll(strings.TrimSuffix(absPath, "/"), " ", "-"))
		name = sanitizeName(name)

		if err := config.AddProject(config.ProjectsFile(), name, absPath); err != nil {
			return err
		}
		ilog.Info(fmt.Sprintf("Added project '%s' at %s", name, absPath))
		return nil
	},
}

var removeCmd = &cobra.Command{
	Use:   "remove <project>",
	Short: "Remove a project from projects.conf",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		name := args[0]
		if err := config.RemoveProject(config.ProjectsFile(), name); err != nil {
			return err
		}
		ilog.Info(fmt.Sprintf("Removed project '%s'", name))
		return nil
	},
}

func realpath(path string) (string, error) {
	if _, err := os.Stat(path); err != nil {
		return "", err
	}
	out, err := exec.Command("realpath", path).Output()
	if err != nil {
		// fallback
		abs, err2 := filepath_abs(path)
		return abs, err2
	}
	return strings.TrimSpace(string(out)), nil
}

func filepath_abs(path string) (string, error) {
	if strings.HasPrefix(path, "/") {
		return path, nil
	}
	cwd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	return cwd + "/" + path, nil
}

// sanitizeName replaces characters not in [a-zA-Z0-9_.-] with -.
func sanitizeName(s string) string {
	var b strings.Builder
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') ||
			(r >= '0' && r <= '9') || r == '_' || r == '.' || r == '-' {
			b.WriteRune(r)
		} else {
			b.WriteRune('-')
		}
	}
	return b.String()
}
