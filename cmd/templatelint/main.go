package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"cdr.dev/slog"
	"cdr.dev/slog/sloggers/sloghuman"
	"golang.org/x/xerrors"
)

var logger = slog.Make(sloghuman.Sink(os.Stdout))

func main() {
	var (
		path        string
		fixIssues   bool
		showHelp    bool
		jsonOutput  bool
	)

	flag.StringVar(&path, "path", "", "Path to template README.md file or directory containing templates")
	flag.BoolVar(&fixIssues, "fix", false, "Attempt to fix common issues automatically")
	flag.BoolVar(&showHelp, "help", false, "Show help message")
	flag.BoolVar(&jsonOutput, "json", false, "Output results in JSON format")
	flag.Parse()

	if showHelp {
		printHelp()
		os.Exit(0)
	}

	if path == "" {
		logger.Error(nil, "path is required")
		printHelp()
		os.Exit(1)
	}

	// Get list of files to check
	files, err := getReadmeFiles(path)
	if err != nil {
		logger.Error(nil, "failed to get README files", "error", err)
		os.Exit(1)
	}

	hasErrors := false
	for _, file := range files {
		errs := lintFile(file, fixIssues, jsonOutput)
		if len(errs) > 0 {
			hasErrors = true
		}
	}

	if hasErrors {
		os.Exit(1)
	}
}

func printHelp() {
	fmt.Println(`Template README Linter

Usage:
  templatelint [options] -path <path>

Options:
  -path string    Path to template README.md file or directory containing templates
  -fix           Attempt to fix common issues automatically
  -json          Output results in JSON format
  -help          Show this help message

Examples:
  # Lint a single README
  templatelint -path ./registry/myuser/templates/mytemplate/README.md

  # Lint all templates in a directory
  templatelint -path ./registry/myuser/templates

  # Lint and attempt to fix issues
  templatelint -path ./README.md -fix

  # Output results in JSON format
  templatelint -path ./README.md -json`)
}

func getReadmeFiles(path string) ([]string, error) {
	var files []string

	fileInfo, err := os.Stat(path)
	if err != nil {
		return nil, xerrors.Errorf("failed to stat path: %w", err)
	}

	if !fileInfo.IsDir() {
		// Single file mode
		if !strings.EqualFold(filepath.Base(path), "README.md") {
			return nil, xerrors.New("specified file must be named README.md")
		}
		return []string{path}, nil
	}

	// Directory mode - walk and find README.md files
	err = filepath.Walk(path, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() && strings.EqualFold(info.Name(), "README.md") {
			// Only include files that are in a templates directory
			if strings.Contains(path, "templates") {
				files = append(files, path)
			}
		}
		return nil
	})

	if err != nil {
		return nil, xerrors.Errorf("failed to walk directory: %w", err)
	}

	return files, nil
}

func lintFile(path string, fix, jsonOutput bool) []error {
	content, err := os.ReadFile(path)
	if err != nil {
		return []error{xerrors.Errorf("failed to read file: %w", err)}
	}

	// Create a readme struct
	rm := readme{
		filePath: path,
		rawText:  string(content),
	}

	// Parse as template readme
	templateReadme, err := parseTemplateReadme(rm)
	if err != nil {
		return []error{xerrors.Errorf("failed to parse template README: %w", err)}
	}

	// Get lint results
	results := lintTemplateReadme(templateReadme.body)

	if jsonOutput {
		printJsonResults(path, results)
		return nil
	}

	// Print results
	fmt.Printf("\nLinting %s:\n", path)
	hasErrors := false
	
	for _, result := range results {
		if len(result.errors) > 0 {
			hasErrors = true
			fmt.Printf("\n[ERROR] %s:\n", result.section)
			for _, err := range result.errors {
				fmt.Printf("  - %s\n", err)
			}
		}
		
		if len(result.suggestions) > 0 {
			fmt.Printf("\n[SUGGESTIONS] %s:\n", result.section)
			for _, suggestion := range result.suggestions {
				fmt.Printf("  - %s\n", suggestion)
			}
		}
	}

	if !hasErrors {
		fmt.Printf("\n✅ No errors found!\n")
		return nil
	}

	if fix {
		// TODO: Implement auto-fixing
		fmt.Println("\nAuto-fix not yet implemented")
	}

	var errs []error
	for _, result := range results {
		for _, err := range result.errors {
			errs = append(errs, xerrors.New(err))
		}
	}
	return errs
}

func printJsonResults(path string, results []lintResult) {
	// TODO: Implement JSON output format
	fmt.Printf("{\n  \"path\": %q,\n  \"results\": [\n", path)
	for i, result := range results {
		fmt.Printf("    {\n      \"section\": %q,\n", result.section)
		fmt.Printf("      \"errors\": %#v,\n", result.errors)
		fmt.Printf("      \"suggestions\": %#v\n    }", result.suggestions)
		if i < len(results)-1 {
			fmt.Print(",")
		}
		fmt.Println()
	}
	fmt.Println("  ]\n}")
}
