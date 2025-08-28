package main

import (
	"bufio"
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
	operatingSystems       = []string{"windows", "macos", "linux"}
	gfmAlertTypes          = []string{"NOTE", "IMPORTANT", "CAUTION", "WARNING", "TIP"}

	// TODO: This is a holdover from the validation logic used by the Coder Modules repo. It gives us some assurance, but
	// realistically, we probably want to parse any Terraform code snippets, and make some deeper guarantees about how it's
	// structured. Just validating whether it *can* be parsed as Terraform would be a big improvement.
	terraformVersionRe = regexp.MustCompile(`^\s*\bversion\s+=`)

	// Matches the format "> [!INFO]". Deliberately using a broad pattern to catch formatting issues that can mess up
	// the renderer for the Registry website
	gfmAlertRegex = regexp.MustCompile(`^>(\s*)\[!(\w+)\](\s*)(.*)`)
)

type coderResourceFrontmatter struct {
	Description      string   `yaml:"description"`
	IconURL          string   `yaml:"icon"`
	DisplayName      *string  `yaml:"display_name"`
	Verified         *bool    `yaml:"verified"`
	Tags             []string `yaml:"tags"`
	OperatingSystems []string `yaml:"supported_os"`
}

// A slice version of the struct tags from coderResourceFrontmatter. Might be worth using reflection to generate this
// list at runtime in the future, but this should be okay for now
var supportedCoderResourceStructKeys = []string{
	"description", "icon", "display_name", "verified", "tags", "supported_os",
	// TODO: This is an old, officially deprecated key from the archived coder/modules repo. We can remove this once we
	// make sure that the Registry Server is no longer checking this field.
	"maintainer_github",
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

func validateSupportedOperatingSystems(systems []string) []error {
	var errs []error
	for _, s := range systems {
		if slices.Contains(operatingSystems, s) {
			continue
		}
		errs = append(errs, xerrors.Errorf("detected unknown operating system %q", s))
	}
	return errs
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

	var errs []error

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
	var invalidTags []string
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

func validateCoderResourceFrontmatter(resourceType string, filePath string, fm coderResourceFrontmatter) []error {
	if !slices.Contains(supportedResourceTypes, resourceType) {
		return []error{xerrors.Errorf("cannot process unknown resource type %q", resourceType)}
	}

	var errs []error
	if err := validateCoderResourceDisplayName(fm.DisplayName); err != nil {
		errs = append(errs, addFilePathToError(filePath, err))
	}
	if err := validateCoderResourceDescription(fm.Description); err != nil {
		errs = append(errs, addFilePathToError(filePath, err))
	}
	if err := validateCoderResourceTags(fm.Tags); err != nil {
		errs = append(errs, addFilePathToError(filePath, err))
	}

	for _, err := range validateCoderResourceIconURL(fm.IconURL) {
		errs = append(errs, addFilePathToError(filePath, err))
	}
	for _, err := range validateSupportedOperatingSystems(fm.OperatingSystems) {
		errs = append(errs, addFilePathToError(filePath, err))
	}

	return errs
}

func parseCoderResourceReadme(resourceType string, rm readme) (coderResourceReadme, []error) {
	fm, body, err := separateFrontmatter(rm.rawText)
	if err != nil {
		return coderResourceReadme{}, []error{xerrors.Errorf("%q: failed to parse frontmatter: %v", rm.filePath, err)}
	}

	keyErrs := validateFrontmatterYamlKeys(fm, supportedCoderResourceStructKeys)
	if len(keyErrs) != 0 {
		var remapped []error
		for _, e := range keyErrs {
			remapped = append(remapped, addFilePathToError(rm.filePath, e))
		}
		return coderResourceReadme{}, remapped
	}

	yml := coderResourceFrontmatter{}
	if err := yaml.Unmarshal([]byte(fm), &yml); err != nil {
		return coderResourceReadme{}, []error{xerrors.Errorf("%q: failed to parse: %v", rm.filePath, err)}
	}

	return coderResourceReadme{
		resourceType: resourceType,
		filePath:     rm.filePath,
		body:         body,
		frontmatter:  yml,
	}, nil
}

func parseCoderResourceReadmeFiles(resourceType string, rms []readme) ([]coderResourceReadme, error) {
	if !slices.Contains(supportedResourceTypes, resourceType) {
		return nil, xerrors.Errorf("cannot process unknown resource type %q", resourceType)
	}

	resources := map[string]coderResourceReadme{}
	var yamlParsingErrs []error
	for _, rm := range rms {
		p, errs := parseCoderResourceReadme(resourceType, rm)
		if len(errs) != 0 {
			yamlParsingErrs = append(yamlParsingErrs, errs...)
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

	var serialized []coderResourceReadme
	for _, r := range resources {
		serialized = append(serialized, r)
	}
	slices.SortFunc(serialized, func(r1 coderResourceReadme, r2 coderResourceReadme) int {
		return strings.Compare(r1.filePath, r2.filePath)
	})
	return serialized, nil
}

// Todo: Need to beef up this function by grabbing each image/video URL from
// the body's AST.
func validateCoderResourceRelativeURLs(_ []coderResourceReadme) error {
	return nil
}

func aggregateCoderResourceReadmeFiles(resourceType string) ([]readme, error) {
	if !slices.Contains(supportedResourceTypes, resourceType) {
		return nil, xerrors.Errorf("cannot process unknown resource type %q", resourceType)
	}

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

func validateResourceGfmAlerts(readmeBody string) []error {
	trimmed := strings.TrimSpace(readmeBody)
	if trimmed == "" {
		return nil
	}

	var errs []error
	var sourceLine string
	isInsideGfmQuotes := false
	isInsideCodeBlock := false

	lineScanner := bufio.NewScanner(strings.NewReader(trimmed))
	for lineScanner.Scan() {
		sourceLine = lineScanner.Text()

		if strings.HasPrefix(sourceLine, "```") {
			isInsideCodeBlock = !isInsideCodeBlock
			continue
		}
		if isInsideCodeBlock {
			continue
		}

		isInsideGfmQuotes = isInsideGfmQuotes && strings.HasPrefix(sourceLine, "> ")

		currentMatch := gfmAlertRegex.FindStringSubmatch(sourceLine)
		if currentMatch == nil {
			continue
		}

		// Nested GFM alerts is such a weird mistake that it's probably not really safe to keep trying to process the
		// rest of the content, so this will prevent any other validations from happening for the given line
		if isInsideGfmQuotes {
			errs = append(errs, errors.New("registry does not support nested GFM alerts"))
			continue
		}

		leadingWhitespace := currentMatch[1]
		if len(leadingWhitespace) != 1 {
			errs = append(errs, errors.New("GFM alerts must have one space between the '>' and the start of the GFM brackets"))
		}
		isInsideGfmQuotes = true

		alertHeader := currentMatch[2]
		upperHeader := strings.ToUpper(alertHeader)
		if !slices.Contains(gfmAlertTypes, upperHeader) {
			errs = append(errs, xerrors.Errorf("GFM alert type %q is not supported", alertHeader))
		}
		if alertHeader != upperHeader {
			errs = append(errs, xerrors.Errorf("GFM alerts must be in all caps"))
		}

		trailingWhitespace := currentMatch[3]
		if trailingWhitespace != "" {
			errs = append(errs, xerrors.Errorf("GFM alerts must not have any trailing whitespace after the closing bracket"))
		}

		extraContent := currentMatch[4]
		if extraContent != "" {
			errs = append(errs, xerrors.Errorf("GFM alerts must not have any extra content on the same line"))
		}
	}

	if gfmAlertRegex.Match([]byte(sourceLine)) {
		errs = append(errs, xerrors.Errorf("README has an incomplete GFM alert at the end of the file"))
	}

	return errs
}
