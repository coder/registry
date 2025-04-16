package main

import (
	"bufio"
	"errors"
	"strings"
)

const rootRegistryPath = "./registry"

var supportedAvatarFileFormats = []string{".png", ".jpeg", ".jpg", ".gif", ".svg"}

// Readme represents a single README file within the repo (usually within the
// "/registry" directory).
type readme struct {
	filePath string
	rawText  string
}

// separateFrontmatter attempts to separate a README file's frontmatter content
// from the main README body, returning both values in that order. It does not
// validate whether the structure of the frontmatter is valid (i.e., that it's
// structured as YAML).
func separateFrontmatter(readmeText string) (string, string, error) {
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

// validationPhase represents a specific phase during README validation. It is
// expected that each phase is discrete, and errors during one will prevent a
// future phase from starting.
type validationPhase int

const (
	// validationPhaseFileStructureValidation indicates when the entire Registry
	// directory is being verified for having all files be placed in the file
	// system as expected.
	validationPhaseFileStructureValidation validationPhase = iota

	// validationPhaseFileLoad indicates when README files are being read from
	// the file system
	validationPhaseFileLoad

	// validationPhaseReadmeParsing indicates when a README's frontmatter is
	// being parsed as YAML. This phase does not include YAML validation.
	validationPhaseReadmeParsing

	// validationPhaseReadmeValidation indicates when a README's frontmatter is
	// being validated as proper YAML with expected keys.
	validationPhaseReadmeValidation

	// validationPhaseAssetCrossReference indicates when a README's frontmatter
	// is having all its relative URLs be validated for whether they point to
	// valid resources.
	validationPhaseAssetCrossReference
)

func (p validationPhase) String() string {
	switch p {
	case validationPhaseFileLoad:
		return "Filesystem reading"
	case validationPhaseReadmeParsing:
		return "README parsing"
	case validationPhaseReadmeValidation:
		return "README validation"
	case validationPhaseAssetCrossReference:
		return "Cross-referencing asset references"
	default:
		return "Unknown validation phase"
	}
}

type zippedReadmes struct {
	old *readme
	new *readme
}

// zipReadmes takes two slices of README files, and combines them into a map,
// where each key is a file path, and each value is a struct containing the old
// value for the path, and the new value for the path. If the old value exists
// but the new one doesn't, that indicates that a file has been deleted. If the
// new value exists, but the old one doesn't, that indicates that the file was
// created.
func zipReadmes(prevReadmes []readme, newReadmes []readme) map[string]zippedReadmes {
	oldMap := map[string]readme{}
	for _, rm := range prevReadmes {
		oldMap[rm.filePath] = rm
	}

	zipped := map[string]zippedReadmes{}
	for _, rm := range newReadmes {
		old, ok := oldMap[rm.filePath]
		if ok {
			zipped[rm.filePath] = zippedReadmes{
				old: &old,
				new: &rm,
			}
		} else {
			zipped[rm.filePath] = zippedReadmes{
				old: nil,
				new: &rm,
			}
		}
	}
	for _, old := range oldMap {
		_, ok := zipped[old.filePath]
		if !ok {
			zipped[old.filePath] = zippedReadmes{
				old: &old,
				new: nil,
			}
		}
	}

	return zipped
}
