package log

import (
	"fmt"
	"os"

	"golang.org/x/term"
)

var (
	bold   = ""
	dim    = ""
	green  = ""
	yellow = ""
	cyan   = ""
	red    = ""
	reset  = ""
)

func init() {
	if term.IsTerminal(int(os.Stdout.Fd())) {
		bold   = "\033[1m"
		dim    = "\033[2m"
		green  = "\033[32m"
		yellow = "\033[33m"
		cyan   = "\033[36m"
		red    = "\033[31m"
		reset  = "\033[0m"
	}
}

func Bold(s string) string   { return bold + s + reset }
func Dim(s string) string    { return dim + s + reset }
func Green(s string) string  { return green + s + reset }
func Yellow(s string) string { return yellow + s + reset }
func Cyan(s string) string   { return cyan + s + reset }
func Red(s string) string    { return red + s + reset }

func Info(msg string) {
	fmt.Printf("%s> %s%s\n", green, msg, reset)
}

func Warn(msg string) {
	fmt.Fprintf(os.Stderr, "%sWarning:%s %s\n", yellow, reset, msg)
}

func Error(msg string) {
	fmt.Fprintf(os.Stderr, "%sError:%s %s\n", red, reset, msg)
}
