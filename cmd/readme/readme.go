package readme

import (
	"bufio"
	"errors"
	"fmt"
	"strings"
)

// Readme represents a single README file within the repo (usually within the
// /registry directory).
type Readme struct {
	FilePath string
	RawText  string
}

// ExtractFrontmatter attempts to separate a README file's frontmatter content
// from the main README body. It does not validate whether the structure of the
// frontmatter is valid (i.e., that it's structured as YAML).
func ExtractFrontmatter(readmeText string) (string, error) {
	if readmeText == "" {
		return "", errors.New("README is empty")
	}

	const fence = "---"
	fm := ""
	fenceCount := 0
	lineScanner := bufio.NewScanner(
		strings.NewReader(strings.TrimSpace(readmeText)),
	)
	for lineScanner.Scan() {
		nextLine := lineScanner.Text()
		if fenceCount == 0 && nextLine != fence {
			return "", errors.New("README does not start with frontmatter fence")
		}

		if nextLine != fence {
			fm += nextLine + "\n"
			continue
		}

		fenceCount++
		if fenceCount >= 2 {
			break
		}
	}

	if fenceCount < 2 {
		return "", errors.New("README does not have two sets of frontmatter fences")
	}
	return fm, nil
}

// ValidationPhase represents a specific phase during README validation. It is
// expected that each phase is discrete, and errors during one will prevent a
// future phase from starting.
type ValidationPhase int

const (
	ValidationPhaseFilesystemRead ValidationPhase = iota
	ValidationPhaseYamlParsing
	ValidationPhaseYamlValidation
	ValidationPhaseAssetCrossReference
)

func (p ValidationPhase) String() string {
	switch p {
	case ValidationPhaseFilesystemRead:
		return "Filesystem reading"
	case ValidationPhaseYamlParsing:
		return "YAML parsing"
	case ValidationPhaseYamlValidation:
		return "YAML validation"
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
