package main

import (
	"bufio"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path"
	"slices"
	"strings"

	"gopkg.in/yaml.v3"
)

const rootRegistryPath = "./registry"

var (
	validContributorStatuses   = []string{"official", "partner", "community"}
	supportedAvatarFileFormats = []string{".png", ".jpeg", ".jpg", ".gif", ".svg"}
)

type readme struct {
	filePath string
	rawText  string
}

type contributorProfileFrontmatter struct {
	DisplayName    string `yaml:"display_name"`
	Bio            string `yaml:"bio"`
	GithubUsername string `yaml:"github"`
	// Script assumes that if value is nil, the Registry site build step will
	// backfill the value with the user's GitHub avatar URL
	AvatarURL              *string `yaml:"avatar"`
	LinkedinURL            *string `yaml:"linkedin"`
	WebsiteURL             *string `yaml:"website"`
	SupportEmail           *string `yaml:"support_email"`
	EmployerGithubUsername *string `yaml:"employer_github"`
	ContributorStatus      *string `yaml:"status"`
}

type contributorProfile struct {
	frontmatter contributorProfileFrontmatter
	filePath    string
}

var _ error = validationPhaseError{}

type validationPhaseError struct {
	phase  string
	errors []error
}

func (vpe validationPhaseError) Error() string {
	validationStrs := []string{}
	for _, e := range vpe.errors {
		validationStrs = append(validationStrs, fmt.Sprintf("- %v", e))
	}
	slices.Sort(validationStrs)

	msg := fmt.Sprintf("Error during %q phase of README validation:", vpe.phase)
	msg += strings.Join(validationStrs, "\n")
	msg += "\n"

	return msg
}

func extractFrontmatter(readmeText string) (string, error) {
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

	if fenceCount == 1 {
		return "", errors.New("README does not have two sets of frontmatter fences")
	}
	return fm, nil
}

func validateContributorGithubUsername(githubUsername string) error {
	if githubUsername == "" {
		return errors.New("missing GitHub username")
	}

	lower := strings.ToLower(githubUsername)
	if uriSafe := url.PathEscape(lower); uriSafe != lower {
		return fmt.Errorf("gitHub username %q is not a valid URL path segment", githubUsername)
	}

	return nil
}

func validateContributorEmployerGithubUsername(
	employerGithubUsername *string,
	githubUsername string,
) []error {
	if employerGithubUsername == nil {
		return nil
	}

	problems := []error{}
	if *employerGithubUsername == "" {
		problems = append(problems, errors.New("company_github field is defined but has empty value"))
		return problems
	}

	lower := strings.ToLower(*employerGithubUsername)
	if uriSafe := url.PathEscape(lower); uriSafe != lower {
		problems = append(problems, fmt.Errorf("gitHub company username %q is not a valid URL path segment", *employerGithubUsername))
	}

	if *employerGithubUsername == githubUsername {
		problems = append(problems, fmt.Errorf("cannot list own GitHub name (%q) as employer", githubUsername))
	}

	return problems
}

func validateContributorDisplayName(displayName string) error {
	if displayName == "" {
		return fmt.Errorf("missing display_name")
	}

	return nil
}

func validateContributorLinkedinURL(linkedinURL *string) error {
	if linkedinURL == nil {
		return nil
	}

	if _, err := url.ParseRequestURI(*linkedinURL); err != nil {
		return fmt.Errorf("linkedIn URL %q is not valid: %v", *linkedinURL, err)
	}

	return nil
}

func validateContributorSupportEmail(email *string) []error {
	if email == nil {
		return nil
	}

	problems := []error{}

	// Can't 100% validate that this is correct without actually sending
	// an email, and especially with some contributors being individual
	// developers, we don't want to do that on every single run of the CI
	// pipeline. Best we can do is verify the general structure
	username, server, ok := strings.Cut(*email, "@")
	if !ok {
		problems = append(problems, fmt.Errorf("email address %q is missing @ symbol", *email))
		return problems
	}

	if username == "" {
		problems = append(problems, fmt.Errorf("email address %q is missing username", *email))
	}

	domain, tld, ok := strings.Cut(server, ".")
	if !ok {
		problems = append(problems, fmt.Errorf("email address %q is missing period for server segment", *email))
		return problems
	}

	if domain == "" {
		problems = append(problems, fmt.Errorf("email address %q is missing domain", *email))
	}
	if tld == "" {
		problems = append(problems, fmt.Errorf("email address %q is missing top-level domain", *email))
	}
	if strings.Contains(*email, "?") {
		problems = append(problems, errors.New("email is not allowed to contain query parameters"))
	}

	return problems
}

func validateContributorWebsite(websiteURL *string) error {
	if websiteURL == nil {
		return nil
	}

	if _, err := url.ParseRequestURI(*websiteURL); err != nil {
		return fmt.Errorf("linkedIn URL %q is not valid: %v", *websiteURL, err)
	}

	return nil
}

func validateContributorStatus(status *string) error {
	if status == nil {
		return nil
	}

	if !slices.Contains(validContributorStatuses, *status) {
		return fmt.Errorf("contributor status %q is not valid", *status)
	}

	return nil
}

// Can't validate the image actually leads to a valid resource in a pure
// function, but can at least catch obvious problems
func validateContributorAvatarURL(avatarURL *string) []error {
	if avatarURL == nil {
		return nil
	}

	problems := []error{}
	if *avatarURL == "" {
		problems = append(problems, errors.New("avatar URL must be omitted or non-empty string"))
		return problems
	}

	// Have to use .Parse instead of .ParseRequestURI because this is the
	// one field that's allowed to be a relative URL
	if _, err := url.Parse(*avatarURL); err != nil {
		problems = append(problems, fmt.Errorf("URL %q is not a valid relative or absolute URL", *avatarURL))
	}
	if strings.Contains(*avatarURL, "?") {
		problems = append(problems, errors.New("avatar URL is not allowed to contain search parameters"))
	}

	matched := false
	for _, ff := range supportedAvatarFileFormats {
		matched = strings.HasSuffix(*avatarURL, ff)
		if matched {
			break
		}
	}
	if !matched {
		segments := strings.Split(*avatarURL, ".")
		fileExtension := segments[len(segments)-1]
		problems = append(problems, fmt.Errorf("avatar URL '.%s' does not end in a supported file format: [%s]", fileExtension, strings.Join(supportedAvatarFileFormats, ", ")))
	}

	return problems
}

func addFilePathToError(filePath string, err error) error {
	return fmt.Errorf("%q: %v", filePath, err)
}

func validateContributorYaml(yml contributorProfile) []error {
	allProblems := []error{}

	if err := validateContributorGithubUsername(yml.frontmatter.GithubUsername); err != nil {
		allProblems = append(allProblems, addFilePathToError(yml.filePath, err))
	}
	if err := validateContributorDisplayName(yml.frontmatter.DisplayName); err != nil {
		allProblems = append(allProblems, addFilePathToError(yml.filePath, err))
	}
	if err := validateContributorLinkedinURL(yml.frontmatter.LinkedinURL); err != nil {
		allProblems = append(allProblems, addFilePathToError(yml.filePath, err))
	}
	if err := validateContributorWebsite(yml.frontmatter.WebsiteURL); err != nil {
		allProblems = append(allProblems, addFilePathToError(yml.filePath, err))
	}
	if err := validateContributorStatus(yml.frontmatter.ContributorStatus); err != nil {
		allProblems = append(allProblems, addFilePathToError(yml.filePath, err))
	}

	for _, err := range validateContributorEmployerGithubUsername(yml.frontmatter.EmployerGithubUsername, yml.frontmatter.GithubUsername) {
		allProblems = append(allProblems, addFilePathToError(yml.filePath, err))
	}
	for _, err := range validateContributorSupportEmail(yml.frontmatter.SupportEmail) {
		allProblems = append(allProblems, addFilePathToError(yml.filePath, err))
	}
	for _, err := range validateContributorAvatarURL(yml.frontmatter.AvatarURL) {
		allProblems = append(allProblems, addFilePathToError(yml.filePath, err))
	}

	return allProblems
}

func parseContributorProfile(rm readme) (contributorProfile, error) {
	fm, err := extractFrontmatter(rm.rawText)
	if err != nil {
		return contributorProfile{}, fmt.Errorf("%q: failed to parse frontmatter: %v", rm.filePath, err)
	}

	yml := contributorProfileFrontmatter{}
	if err := yaml.Unmarshal([]byte(fm), &yml); err != nil {
		return contributorProfile{}, fmt.Errorf("%q: failed to parse: %v", rm.filePath, err)
	}

	return contributorProfile{
		filePath:    rm.filePath,
		frontmatter: yml,
	}, nil
}

func parseContributorFiles(readmeEntries []readme) (map[string]contributorProfile, error) {
	profilesByUsername := map[string]contributorProfile{}
	yamlParsingErrors := []error{}
	for _, rm := range readmeEntries {
		p, err := parseContributorProfile(rm)
		if err != nil {
			yamlParsingErrors = append(yamlParsingErrors, err)
			continue
		}

		if prev, alreadyExists := profilesByUsername[p.frontmatter.GithubUsername]; alreadyExists {
			yamlParsingErrors = append(yamlParsingErrors, fmt.Errorf("%q: GitHub name %s conflicts with field defined in %q", p.filePath, p.frontmatter.GithubUsername, prev.filePath))
			continue
		}
		profilesByUsername[p.frontmatter.GithubUsername] = p
	}
	if len(yamlParsingErrors) != 0 {
		return nil, validationPhaseError{
			phase:  "YAML parsing",
			errors: yamlParsingErrors,
		}
	}

	employeeGithubGroups := map[string][]string{}
	yamlValidationErrors := []error{}
	for _, p := range profilesByUsername {
		errors := validateContributorYaml(p)
		if len(errors) > 0 {
			yamlValidationErrors = append(yamlValidationErrors, errors...)
			continue
		}

		if p.frontmatter.EmployerGithubUsername != nil {
			employeeGithubGroups[*p.frontmatter.EmployerGithubUsername] = append(
				employeeGithubGroups[*p.frontmatter.EmployerGithubUsername],
				p.frontmatter.GithubUsername,
			)
		}
	}
	for companyName, group := range employeeGithubGroups {
		if _, found := profilesByUsername[companyName]; found {
			continue
		}
		yamlValidationErrors = append(yamlValidationErrors, fmt.Errorf("company %q does not exist in %q directory but is referenced by these profiles: [%s]", companyName, rootRegistryPath, strings.Join(group, ", ")))
	}
	if len(yamlValidationErrors) != 0 {
		return nil, validationPhaseError{
			phase:  "Raw YAML Validation",
			errors: yamlValidationErrors,
		}
	}

	return profilesByUsername, nil
}

func aggregateContributorReadmeFiles() ([]readme, error) {
	dirEntries, err := os.ReadDir(rootRegistryPath)
	if err != nil {
		return nil, err
	}

	allReadmeFiles := []readme{}
	problems := []error{}
	for _, e := range dirEntries {
		dirPath := path.Join(rootRegistryPath, e.Name())
		if !e.IsDir() {
			problems = append(problems, fmt.Errorf("detected non-directory file %q at base of main Registry directory", dirPath))
			continue
		}

		readmePath := path.Join(dirPath, "README.md")
		rmBytes, err := os.ReadFile(readmePath)
		if err != nil {
			problems = append(problems, err)
			continue
		}
		allReadmeFiles = append(allReadmeFiles, readme{
			filePath: readmePath,
			rawText:  string(rmBytes),
		})
	}

	if len(problems) != 0 {
		return nil, validationPhaseError{
			phase:  "FileSystem reading",
			errors: problems,
		}
	}

	return allReadmeFiles, nil
}

func validateRelativeUrls(
	contributors map[string]contributorProfile,
) error {
	// This function only validates relative avatar URLs for now, but it can be
	// beefed up to validate more in the future
	problems := []error{}

	for _, con := range contributors {
		// If the avatar URL is missing, we'll just assume that the Registry
		// site build step will take care of filling in the data properly
		if con.frontmatter.AvatarURL == nil {
			continue
		}
		if isRelativeURL := strings.HasPrefix(*con.frontmatter.AvatarURL, ".") ||
			strings.HasPrefix(*con.frontmatter.AvatarURL, "/"); !isRelativeURL {
			continue
		}

		if strings.HasPrefix(*con.frontmatter.AvatarURL, "..") {
			problems = append(problems, fmt.Errorf("%q: relative avatar URLs cannot be placed outside a user's namespaced directory", con.filePath))
			continue
		}

		absolutePath := strings.TrimSuffix(con.filePath, "README.md") +
			*con.frontmatter.AvatarURL
		_, err := os.ReadFile(absolutePath)
		if err != nil {
			problems = append(problems, fmt.Errorf("%q: relative avatar path %q does not point to image in file system", con.filePath, *con.frontmatter.AvatarURL))
		}
	}

	if len(problems) == 0 {
		return nil
	}
	return validationPhaseError{
		phase:  "Relative URL validation",
		errors: problems,
	}
}
