package config

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"gopkg.in/ini.v1"
)

// Project represents a configured project entry.
type Project struct {
	Name        string
	Path        string
	SessionName string
	OnCreate    []string
	MaxDepth    int
}

// Defaults holds fallback values from the [DEFAULT] section.
type Defaults struct {
	SessionName string
	OnCreate    []string
}

// Settings holds values from the flat settings config file.
type Settings struct {
	AutoAddClone bool
	FzfHeight    string
}

// ConfigDir returns the txs config directory, respecting XDG_CONFIG_HOME.
func ConfigDir() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "txs")
}

// ProjectsFile returns the path to projects.conf.
func ProjectsFile() string {
	return filepath.Join(ConfigDir(), "projects.conf")
}

// SettingsFile returns the path to the settings config file.
func SettingsFile() string {
	return filepath.Join(ConfigDir(), "config")
}

// ExpandPath expands a leading ~ to the user's home directory.
func ExpandPath(path string) string {
	if strings.HasPrefix(path, "~/") {
		return filepath.Join(os.Getenv("HOME"), path[2:])
	}
	if path == "~" {
		return os.Getenv("HOME")
	}
	return path
}

// SanitizeSessionName replaces characters tmux substitutes (. and :) with _.
func SanitizeSessionName(name string) string {
	r := strings.NewReplacer(".", "_", ":", "_")
	return r.Replace(name)
}

var validSectionName = regexp.MustCompile(`^[a-zA-Z0-9_.:-]+$`)

// ParseProjects parses projects.conf and returns an ordered slice of Projects
// plus the DEFAULT section values. Duplicate section names are deduplicated,
// keeping the last occurrence (matching the shell implementation).
func ParseProjects(path string) ([]Project, Defaults, error) {
	defaults := Defaults{}

	cfg, err := ini.LoadSources(ini.LoadOptions{
		AllowShadows:             false,
		SpaceBeforeInlineComment: true,
		AllowNestedValues:        true,
		AllowPythonMultilineValues: true,
	}, path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, defaults, nil
		}
		return nil, defaults, fmt.Errorf("parsing %s: %w", path, err)
	}

	// Parse DEFAULT section
	defSec := cfg.Section("DEFAULT")
	if defSec != nil {
		if defSec.HasKey("session_name") {
			defaults.SessionName = defSec.Key("session_name").String()
		}
		if defSec.HasKey("on_create") {
			defaults.OnCreate = parseOnCreate(defSec.Key("on_create").String())
		}
	}

	// Use an ordered map: last definition of a section name wins.
	type entry struct {
		index   int
		project Project
	}
	seen := map[string]*entry{}
	order := []string{}

	for _, sec := range cfg.Sections() {
		name := sec.Name()
		if name == "DEFAULT" || name == ini.DefaultSection {
			continue
		}
		if !validSectionName.MatchString(name) {
			continue
		}

		p := Project{Name: name}

		if sec.HasKey("path") {
			p.Path = ExpandPath(sec.Key("path").String())
		}
		if sec.HasKey("max_depth") {
			p.MaxDepth, _ = sec.Key("max_depth").Int()
		}
		if sec.HasKey("on_create") {
			p.OnCreate = parseOnCreate(sec.Key("on_create").String())
		}

		// session_name: explicit > DEFAULT > section name; sanitize like tmux
		sessionName := ""
		if sec.HasKey("session_name") {
			sessionName = sec.Key("session_name").String()
		} else if defaults.SessionName != "" {
			sessionName = defaults.SessionName
		} else {
			sessionName = name
		}
		p.SessionName = SanitizeSessionName(sessionName)

		if e, exists := seen[name]; exists {
			// Replace existing entry in-place (last wins, preserving first position)
			e.project = p
		} else {
			idx := len(order)
			order = append(order, name)
			seen[name] = &entry{index: idx, project: p}
		}
	}

	projects := make([]Project, len(order))
	for i, name := range order {
		projects[i] = seen[name].project
	}

	return projects, defaults, nil
}

// parseOnCreate splits a (possibly multi-line) on_create value into individual
// commands, trimming each line and dropping empty ones.
func parseOnCreate(raw string) []string {
	lines := strings.Split(raw, "\n")
	result := []string{}
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line != "" {
			result = append(result, line)
		}
	}
	return result
}

// ParseSettings reads the flat key=value settings file.
func ParseSettings(path string) (Settings, error) {
	s := Settings{
		AutoAddClone: true,
		FzfHeight:    "50%",
	}

	cfg, err := ini.LoadSources(ini.LoadOptions{
		SpaceBeforeInlineComment: true,
	}, path)
	if err != nil {
		if os.IsNotExist(err) {
			return s, nil
		}
		return s, fmt.Errorf("parsing settings %s: %w", path, err)
	}

	sec := cfg.Section("")
	if sec.HasKey("auto_add_clone") {
		s.AutoAddClone = sec.Key("auto_add_clone").MustBool(true)
	}
	if sec.HasKey("fzf_height") {
		s.FzfHeight = sec.Key("fzf_height").String()
	}
	return s, nil
}

// AddProject appends a new project section to projects.conf.
func AddProject(cfgPath, name, path string) error {
	if err := os.MkdirAll(filepath.Dir(cfgPath), 0o755); err != nil {
		return err
	}

	cfg, err := ini.LoadSources(ini.LoadOptions{
		AllowPythonMultilineValues: true,
		Loose:                      true,
	}, cfgPath)
	if err != nil {
		if !os.IsNotExist(err) {
			return fmt.Errorf("loading %s: %w", cfgPath, err)
		}
		cfg = ini.Empty()
	}

	if cfg.HasSection(name) {
		return fmt.Errorf("project '%s' already exists in config", name)
	}

	sec, err := cfg.NewSection(name)
	if err != nil {
		return err
	}
	if _, err := sec.NewKey("path", path); err != nil {
		return err
	}

	return cfg.SaveTo(cfgPath)
}

// RemoveProject removes a project section from projects.conf.
func RemoveProject(cfgPath, name string) error {
	cfg, err := ini.LoadSources(ini.LoadOptions{
		AllowPythonMultilineValues: true,
		Loose:                      true,
	}, cfgPath)
	if err != nil {
		return fmt.Errorf("loading %s: %w", cfgPath, err)
	}

	if !cfg.HasSection(name) {
		return fmt.Errorf("project '%s' not found in config", name)
	}

	cfg.DeleteSection(name)
	return cfg.SaveTo(cfgPath)
}
