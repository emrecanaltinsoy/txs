package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"
)

const version = "0.5.1"

var rootCmd = &cobra.Command{
	Use:           "txs",
	Short:         "tmux session manager for projects",
	Long:          buildHelp(),
	SilenceUsage:  true,
	SilenceErrors: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runInteractive()
	},
}

func buildHelp() string {
	return `txs — tmux session manager for projects

USAGE:
  txs [command] [options]

Session management:
  txs attach [project] [worktree]   Attach to a project tmux session
  txs ls [sessions|projects|worktrees]  List sessions, projects, or worktrees
  txs kill [session|window]         Kill a tmux session or window
  txs switch                        Switch between active tmux sessions

Worktree management:
  txs wt add <branch>               Add a git worktree
  txs wt remove <branch>            Remove a git worktree
  txs wt list                       List git worktrees
  txs clone-bare <url> [name]       Clone a repo as bare with worktree setup

Project management:
  txs add [path]                    Add a directory to projects.conf
  txs remove <project>              Remove a project from projects.conf
  txs config [projects|settings]    Open config file in $EDITOR

ALIASES:
  list      -> ls
  sessions  -> ls sessions
  projects  -> ls projects

Use "txs [command] --help" for more information about a command.`
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		msg := err.Error()
		// Normalize cobra's unknown command message to match expected format
		if strings.HasPrefix(msg, "unknown command") {
			msg = strings.Replace(msg, "unknown command", "Unknown command", 1)
		}
		fmt.Fprintf(os.Stderr, "\033[31mError:\033[0m %s\n", msg)
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().BoolP("version", "v", false, "Print version and exit")
	rootCmd.PersistentPreRunE = func(cmd *cobra.Command, args []string) error {
		v, _ := cmd.Flags().GetBool("version")
		if v {
			fmt.Println(version)
			os.Exit(0)
		}
		return nil
	}

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
	Use:   "version",
	Short: "Print version",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println(version)
	},
}
