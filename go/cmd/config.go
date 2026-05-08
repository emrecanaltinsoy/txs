package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/emrecanaltinsoy/txs/internal/config"
	ilog "github.com/emrecanaltinsoy/txs/internal/log"
	"github.com/spf13/cobra"
)

var configCmd = &cobra.Command{
	Use:       "config [projects|settings]",
	Short:     "Open projects.conf or settings file in $EDITOR",
	Args:      cobra.MaximumNArgs(1),
	ValidArgs: []string{"projects", "settings"},
	RunE: func(cmd *cobra.Command, args []string) error {
		target := "projects"
		if len(args) > 0 {
			target = args[0]
		}

		var path string
		switch target {
		case "projects":
			path = config.ProjectsFile()
		case "settings":
			path = config.SettingsFile()
		default:
			return fmt.Errorf("Unknown config target '%s'. Use: projects, settings", target)
		}

		// Ensure the file exists
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return err
		}
		f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY, 0o644)
		if err != nil {
			return err
		}
		f.Close()

		ilog.Info(fmt.Sprintf("Opening %s", path))
		return openEditor(path)
	},
}
