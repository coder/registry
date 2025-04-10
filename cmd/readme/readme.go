// Package readme contains general-use utilities for processing README files.
package readme

import (
	"bufio"
	"errors"
	"fmt"
	"strings"
)

// RootRegistryPath is the directory where all READMEs that need to be validated
// should live.
const RootRegistryPath = "./registry"

// Readme represents a single README file within the repo (usually within the
// /registry directory).
type Readme struct {
	FilePath string
	RawText  string
}

// SeparateFrontmatter attempts to separate a README file's frontmatter content
// from the main README body, returning both values in that order. It does not
// validate whether the structure of the frontmatter is valid (i.e., that it's
// structured as YAML).
func SeparateFrontmatter(readmeText string) (string, string, error) {
	if readmeText == "" {
		return "", "", errors.New("README is empty")
	}

	const fence = "---"
	fm := ""
	body := ""
	fenceCount := 0
	lineScanner := bufio.NewScanner(
		strings.NewReader(strings.TrimSpace(readmeText)),
	)
	for lineScanner.Scan() {
		nextLine := lineScanner.Text()
		if fenceCount < 2 && nextLine == fence {
			fenceCount++
			continue
		}
		// Break early if the very first line wasn't a fence, because then we
		// know for certain that the README has problems
		if fenceCount == 0 {
			break
		}

		// It should be safe to trim each line of the frontmatter on a per-line
		// basis, because there shouldn't be any extra meaning attached to the
		// indentation. The same does NOT apply to the README; best we can do is
		// gather all the lines, and then trim around it
		if inReadmeBody := fenceCount >= 2; inReadmeBody {
			body += nextLine + "\n"
		} else {
			fm += strings.TrimSpace(nextLine) + "\n"
		}
	}
	if fenceCount < 2 {
		return "", "", errors.New("README does not have two sets of frontmatter fences")
	}
	if fm == "" {
		return "", "", errors.New("readme has frontmatter fences but no frontmatter content")
	}

	return fm, strings.TrimSpace(body), nil
}

// ValidationPhase represents a specific phase during README validation. It is
// expected that each phase is discrete, and errors during one will prevent a
// future phase from starting.
type ValidationPhase int

const (
	// ValidationPhaseFilesystemRead indicates when a README file is being read
	// from the file system
	ValidationPhaseFilesystemRead ValidationPhase = iota
	// ValidationPhaseReadmeParsing indicates when a README's frontmatter is being
	// parsed as YAML. This phase does not include YAML validation.
	ValidationPhaseReadmeParsing
	// ValidationPhaseReadmeValidation indicates when a README's frontmatter is
	// being validated as proper YAML with expected keys.
	ValidationPhaseReadmeValidation
	// ValidationPhaseAssetCrossReference indicates when a README's frontmatter
	// is having all its relative URLs be validated for whether they point to
	// valid resources.
	ValidationPhaseAssetCrossReference
)

func (p ValidationPhase) String() string {
	switch p {
	case ValidationPhaseFilesystemRead:
		return "Filesystem reading"
	case ValidationPhaseReadmeParsing:
		return "README parsing"
	case ValidationPhaseReadmeValidation:
		return "README validation"
	case ValidationPhaseAssetCrossReference:
		return "Cross-referencing asset references"
	default:
		return "Unknown validation phase"
	}
}

var _ error = ValidationPhaseError{}

// ValidationPhaseError represents an error that occurred during a specific
// phase of README validation. It should be used to collect ALL validation
// errors that happened during a specific phase, rather than the first one
// encountered.
type ValidationPhaseError struct {
	Phase  ValidationPhase
	Errors []error
}

func (vpe ValidationPhaseError) Error() string {
	msg := fmt.Sprintf("Error during %q phase of README validation:", vpe.Phase.String())
	for _, e := range vpe.Errors {
		msg += fmt.Sprintf("\n- %v", e)
	}
	msg += "\n"

	return msg
}
