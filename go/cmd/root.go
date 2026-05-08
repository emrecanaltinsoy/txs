package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

const version = "0.6.0-go"

var rootCmd = &cobra.Command{
	Use:           "txs",
	Short:         "tmux session manager for projects",
	Long:          "txs — manage tmux sessions tied to your project directories.",
	SilenceUsage:  true,
	SilenceErrors: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runInteractive()
	},
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "\033[31mError:\033[0m %s\n", err)
		os.Exit(1)
	}
}

func init() {
	// version / aliases
	rootCmd.AddCommand(versionCmd)
	rootCmd.AddCommand(attachCmd)
	rootCmd.AddCommand(switchCmd)
	rootCmd.AddCommand(lsCmd)
	rootCmd.AddCommand(listCmd)     // alias for ls
	rootCmd.AddCommand(sessionsCmd) // alias for ls sessions
	rootCmd.AddCommand(projectsCmd) // alias for ls projects
	rootCmd.AddCommand(killCmd)
	rootCmd.AddCommand(wtCmd)
	rootCmd.AddCommand(addCmd)
	rootCmd.AddCommand(removeCmd)
	rootCmd.AddCommand(cloneBareCmd)
	rootCmd.AddCommand(configCmd)
}

var versionCmd = &cobra.Command{
	Use:     "version",
	Aliases: []string{"--version", "-v"},
	Short:   "Print version",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println(version)
	},
}
