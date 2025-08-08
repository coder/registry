package main

import (
	"bufio"
	"context"
	"errors"
	"net/url"
	"os"
	"path"
	"regexp"
	"slices"
	"strings"

	"golang.org/x/xerrors"
	"gopkg.in/yaml.v3"
)

var (
	supportedResourceTypes = []string{"modules", "templates"}

	// TODO: This is a holdover from the validation logic used by the Coder Modules repo. It gives us some assurance, but
	// realistically, we probably want to parse any Terraform code snippets, and make some deeper guarantees about how it's
	// structured. Just validating whether it *can* be parsed as Terraform would be a big improvement.
	terraformVersionRe = regexp.MustCompile(`^\s*\bversion\s+=`)
)

type coderResourceFrontmatter struct {
	Description string   `yaml:"description"`
	IconURL     string   `yaml:"icon"`
	DisplayName *string  `yaml:"display_name"`
	Verified    *bool    `yaml:"verified"`
	Tags        []string `yaml:"tags"`
}

// coderResourceReadme represents a README describing a Terraform resource used
// to help create Coder workspaces. As of 2025-04-15, this encapsulates both
// Coder Modules and Coder Templates.
type coderResourceReadme struct {
	resourceType string
	filePath     string
	body         string
	frontmatter  coderResourceFrontmatter
}

func validateCoderResourceDisplayName(displayName *string) error {
	if displayName != nil && *displayName == "" {
		return xerrors.New("if defined, display_name must not be empty string")
	}
	return nil
}

func validateCoderResourceDescription(description string) error {
	if description == "" {
		return xerrors.New("frontmatter description cannot be empty")
	}
	return nil
}

func isPermittedRelativeURL(checkURL string) bool {
	// Would normally be skittish about having relative paths like this, but it should be safe because we have
	// guarantees about the structure of the repo, and where this logic will run.
	return strings.HasPrefix(checkURL, "./") || strings.HasPrefix(checkURL, "/") || strings.HasPrefix(checkURL, "../../../../.icons")
}

func validateCoderResourceIconURL(iconURL string) []error {
	if iconURL == "" {
		return []error{xerrors.New("icon URL cannot be empty")}
	}

	errs := []error{}

	// If the URL does not have a relative path.
	if !strings.HasPrefix(iconURL, ".") && !strings.HasPrefix(iconURL, "/") {
		if _, err := url.ParseRequestURI(iconURL); err != nil {
			errs = append(errs, xerrors.New("absolute icon URL is not correctly formatted"))
		}
		if strings.Contains(iconURL, "?") {
			errs = append(errs, xerrors.New("icon URLs cannot contain query parameters"))
		}
		return errs
	}

	// If the URL has a relative path.
	if !isPermittedRelativeURL(iconURL) {
		errs = append(errs, xerrors.Errorf("relative icon URL %q must either be scoped to that module's directory, or the top-level /.icons directory (this can usually be done by starting the path with \"../../../.icons\")", iconURL))
	}

	return errs
}

func validateCoderResourceTags(tags []string) error {
	if tags == nil {
		return xerrors.New("provided tags array is nil")
	}
	if len(tags) == 0 {
		return nil
	}

	// All of these tags are used for the module/template filter controls in the Registry site. Need to make sure they
	// can all be placed in the browser URL without issue.
	invalidTags := []string{}
	for _, t := range tags {
		if t != url.QueryEscape(t) {
			invalidTags = append(invalidTags, t)
		}
	}

	if len(invalidTags) != 0 {
		return xerrors.Errorf("found invalid tags (tags that cannot be used for filter state in the Registry website): [%s]", strings.Join(invalidTags, ", "))
	}
	return nil
}

func validateCoderResourceReadmeBody(body string) []error {
	var errs []error

	trimmed := strings.TrimSpace(body)
	// TODO: this may cause unexpected behavior since the errors slice may have a 0 length. Add a test.
	errs = append(errs, validateReadmeBody(trimmed)...)

	foundParagraph := false
	terraformCodeBlockCount := 0
	foundTerraformVersionRef := false

	lineNum := 0
	isInsideCodeBlock := false
	isInsideTerraform := false

	lineScanner := bufio.NewScanner(strings.NewReader(trimmed))
	for lineScanner.Scan() {
		lineNum++
		nextLine := lineScanner.Text()

		// Code assumes that invalid headers would've already been handled by the base validation function, so we don't
		// need to check deeper if the first line isn't an h1.
		if lineNum == 1 {
			if !strings.HasPrefix(nextLine, "# ") {
				break
			}
			continue
		}

		if strings.HasPrefix(nextLine, "```") {
			isInsideCodeBlock = !isInsideCodeBlock
			isInsideTerraform = isInsideCodeBlock && strings.HasPrefix(nextLine, "```tf")
			if isInsideTerraform {
				terraformCodeBlockCount++
			}
			if strings.HasPrefix(nextLine, "```hcl") {
				errs = append(errs, xerrors.New("all .hcl language references must be converted to .tf"))
			}
			continue
		}

		if isInsideCodeBlock {
			if isInsideTerraform {
				foundTerraformVersionRef = foundTerraformVersionRef || terraformVersionRe.MatchString(nextLine)
			}
			continue
		}

		// Code assumes that we can treat this case as the end of the "h1 section" and don't need to process any further lines.
		if lineNum > 1 && strings.HasPrefix(nextLine, "#") {
			break
		}

		// Code assumes that if we've reached this point, the only other options are:
		// (1) empty spaces, (2) paragraphs, (3) HTML, and (4) asset references made via [] syntax.
		trimmedLine := strings.TrimSpace(nextLine)
		isParagraph := trimmedLine != "" && !strings.HasPrefix(trimmedLine, "![") && !strings.HasPrefix(trimmedLine, "<")
		foundParagraph = foundParagraph || isParagraph
	}

	if terraformCodeBlockCount == 0 {
		errs = append(errs, xerrors.New("did not find Terraform code block within h1 section"))
	} else {
		if terraformCodeBlockCount > 1 {
			errs = append(errs, xerrors.New("cannot have more than one Terraform code block in h1 section"))
		}
		if !foundTerraformVersionRef {
			errs = append(errs, xerrors.New("did not find Terraform code block that specifies 'version' field"))
		}
	}
	if !foundParagraph {
		errs = append(errs, xerrors.New("did not find paragraph within h1 section"))
	}
	if isInsideCodeBlock {
		errs = append(errs, xerrors.New("code blocks inside h1 section do not all terminate before end of file"))
	}

	return errs
}

func validateCoderResourceReadme(rm coderResourceReadme) []error {
	var errs []error

	for _, err := range validateCoderResourceReadmeBody(rm.body) {
		errs = append(errs, addFilePathToError(rm.filePath, err))
	}

	if err := validateCoderResourceDisplayName(rm.frontmatter.DisplayName); err != nil {
		errs = append(errs, addFilePathToError(rm.filePath, err))
	}
	if err := validateCoderResourceDescription(rm.frontmatter.Description); err != nil {
		errs = append(errs, addFilePathToError(rm.filePath, err))
	}
	if err := validateCoderResourceTags(rm.frontmatter.Tags); err != nil {
		errs = append(errs, addFilePathToError(rm.filePath, err))
	}

	for _, err := range validateCoderResourceIconURL(rm.frontmatter.IconURL) {
		errs = append(errs, addFilePathToError(rm.filePath, err))
	}

	return errs
}

func parseCoderResourceReadme(resourceType string, rm readme) (coderResourceReadme, error) {
	fm, body, err := separateFrontmatter(rm.rawText)
	if err != nil {
		return coderResourceReadme{}, xerrors.Errorf("%q: failed to parse frontmatter: %v", rm.filePath, err)
	}

	yml := coderResourceFrontmatter{}
	if err := yaml.Unmarshal([]byte(fm), &yml); err != nil {
		return coderResourceReadme{}, xerrors.Errorf("%q: failed to parse: %v", rm.filePath, err)
	}

	return coderResourceReadme{
		resourceType: resourceType,
		filePath:     rm.filePath,
		body:         body,
		frontmatter:  yml,
	}, nil
}

func parseCoderResourceReadmeFiles(resourceType string, rms []readme) (map[string]coderResourceReadme, error) {
	resources := map[string]coderResourceReadme{}
	var yamlParsingErrs []error
	for _, rm := range rms {
		p, err := parseCoderResourceReadme(resourceType, rm)
		if err != nil {
			yamlParsingErrs = append(yamlParsingErrs, err)
			continue
		}

		resources[p.filePath] = p
	}
	if len(yamlParsingErrs) != 0 {
		return nil, validationPhaseError{
			phase:  validationPhaseReadme,
			errors: yamlParsingErrs,
		}
	}

	yamlValidationErrors := []error{}
	for _, readme := range resources {
		errs := validateCoderResourceReadme(readme)
		if len(errs) > 0 {
			yamlValidationErrors = append(yamlValidationErrors, errs...)
		}
	}
	if len(yamlValidationErrors) != 0 {
		return nil, validationPhaseError{
			phase:  validationPhaseReadme,
			errors: yamlValidationErrors,
		}
	}

	return resources, nil
}

// Todo: Need to beef up this function by grabbing each image/video URL from
// the body's AST.
func validateCoderResourceRelativeURLs(_ map[string]coderResourceReadme) error {
	return nil
}

func aggregateCoderResourceReadmeFiles(resourceType string) ([]readme, error) {
	registryFiles, err := os.ReadDir(rootRegistryPath)
	if err != nil {
		return nil, err
	}

	var allReadmeFiles []readme
	var errs []error
	for _, rf := range registryFiles {
		if !rf.IsDir() {
			continue
		}

		resourceRootPath := path.Join(rootRegistryPath, rf.Name(), resourceType)
		resourceDirs, err := os.ReadDir(resourceRootPath)
		if err != nil {
			if !errors.Is(err, os.ErrNotExist) {
				errs = append(errs, err)
			}
			continue
		}

		for _, rd := range resourceDirs {
			if !rd.IsDir() || rd.Name() == ".coder" {
				continue
			}

			resourceReadmePath := path.Join(resourceRootPath, rd.Name(), "README.md")
			rm, err := os.ReadFile(resourceReadmePath)
			if err != nil {
				errs = append(errs, err)
				continue
			}

			allReadmeFiles = append(allReadmeFiles, readme{
				filePath: resourceReadmePath,
				rawText:  string(rm),
			})
		}
	}

	if len(errs) != 0 {
		return nil, validationPhaseError{
			phase:  validationPhaseFile,
			errors: errs,
		}
	}
	return allReadmeFiles, nil
}

func validateAllCoderResourceFilesOfType(resourceType string) error {
	if !slices.Contains(supportedResourceTypes, resourceType) {
		return xerrors.Errorf("resource type %q is not part of supported list [%s]", resourceType, strings.Join(supportedResourceTypes, ", "))
	}

	allReadmeFiles, err := aggregateCoderResourceReadmeFiles(resourceType)
	if err != nil {
		return err
	}

	logger.Info(context.Background(), "processing README files", "num_files", len(allReadmeFiles))
	resources, err := parseCoderResourceReadmeFiles(resourceType, allReadmeFiles)
	if err != nil {
		return err
	}
	logger.Info(context.Background(), "processed README files as valid Coder resources", "num_files", len(resources), "type", resourceType)

	if err := validateCoderResourceRelativeURLs(resources); err != nil {
		return err
	}
	logger.Info(context.Background(), "all relative URLs for READMEs are valid", "type", resourceType)
	return nil
}
