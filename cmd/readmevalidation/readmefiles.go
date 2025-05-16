package main

import (
	"bufio"
	"errors"
	"fmt"
	"regexp"
	"strings"
)

const rootRegistryPath = "./registry"

var supportedAvatarFileFormats = []string{".png", ".jpeg", ".jpg", ".gif", ".svg"}

// readme represents a single README file within the repo (usually within the
// top-level "/registry" directory).
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

	lineScanner := bufio.NewScanner(strings.NewReader(strings.TrimSpace(readmeText)))
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

var readmeHeaderRe = regexp.MustCompile("^(#{1,})(\\s*)")

// Todo: This seems to work okay for now, but the really proper way of doing
// this is by parsing this as an AST, and then checking the resulting nodes
func validateReadmeBody(body string) []error {
	trimmed := strings.TrimSpace(body)

	if trimmed == "" {
		return []error{errors.New("README body is empty")}
	}

	// If the very first line of the README, there's a risk that the rest of the
	// validation logic will break, since we don't have many guarantees about
	// how the README is actually structured
	if !strings.HasPrefix(trimmed, "# ") {
		return []error{errors.New("README body must start with ATX-style h1 header (i.e., \"# \")")}
	}

	var errs []error
	latestHeaderLevel := 0
	foundFirstH1 := false
	isInCodeBlock := false

	lineScanner := bufio.NewScanner(strings.NewReader(trimmed))
	for lineScanner.Scan() {
		nextLine := lineScanner.Text()

		// Have to check this because a lot of programming languages support #
		// comments (including Terraform), and without any context, there's no
		// way to tell the difference between a markdown header and code comment
		if strings.HasPrefix(nextLine, "```") {
			isInCodeBlock = !isInCodeBlock
			continue
		}
		if isInCodeBlock {
			continue
		}

		headerGroups := readmeHeaderRe.FindStringSubmatch(nextLine)
		if headerGroups == nil {
			continue
		}

		spaceAfterHeader := headerGroups[2]
		if spaceAfterHeader == "" {
			errs = append(errs, errors.New("header does not have space between header characters and main header text"))
		}

		nextHeaderLevel := len(headerGroups[1])
		if nextHeaderLevel == 1 && !foundFirstH1 {
			foundFirstH1 = true
			latestHeaderLevel = 1
			continue
		}

		// If we have obviously invalid headers, it's not really safe to keep
		// proceeding with the rest of the content
		if nextHeaderLevel == 1 {
			errs = append(errs, errors.New("READMEs cannot contain more than h1 header"))
			break
		}
		if nextHeaderLevel > 6 {
			errs = append(errs, fmt.Errorf("README/HTML files cannot have headers exceed level 6 (found level %d)", nextHeaderLevel))
			break
		}

		// This is something we need to enforce for accessibility, not just for
		// the Registry website, but also when users are viewing the README
		// files in the GitHub web view
		if nextHeaderLevel > latestHeaderLevel && nextHeaderLevel != (latestHeaderLevel+1) {
			errs = append(errs, fmt.Errorf("headers are not allowed to increase more than 1 level at a time"))
			continue
		}

		// As long as the above condition passes, there's no problems with
		// going up a header level or going down 1+ header levels
		latestHeaderLevel = nextHeaderLevel
	}

	return errs
}

// validationPhase represents a specific phase during README validation. It is
// expected that each phase is discrete, and errors during one will prevent a
// future phase from starting.
type validationPhase string

const (
	// validationPhaseFileStructureValidation indicates when the entire Registry
	// directory is being verified for having all files be placed in the file
	// system as expected.
	validationPhaseFileStructureValidation validationPhase = "File structure validation"

	// validationPhaseFileLoad indicates when README files are being read from
	// the file system
	validationPhaseFileLoad = "Filesystem reading"

	// validationPhaseReadmeParsing indicates when a README's frontmatter is
	// being parsed as YAML. This phase does not include YAML validation.
	validationPhaseReadmeParsing = "README parsing"

	// validationPhaseReadmeValidation indicates when a README's frontmatter is
	// being validated as proper YAML with expected keys.
	validationPhaseReadmeValidation = "README validation"

	// validationPhaseAssetCrossReference indicates when a README's frontmatter
	// is having all its relative URLs be validated for whether they point to
	// valid resources.
	validationPhaseAssetCrossReference = "Cross-referencing relative asset URLs"
)
