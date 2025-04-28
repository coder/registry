package main

import (
	"errors"
	"fmt"
	"log"
	"net/url"
	"os"
	"path"
	"slices"
	"strings"

	"gopkg.in/yaml.v3"
)

var validContributorStatuses = []string{"official", "partner", "community"}

type contributorProfileFrontmatter struct {
	DisplayName string `yaml:"display_name"`
	Bio         string `yaml:"bio"`
	// Script assumes that if value is nil, the Registry site build step will
	// backfill the value with the user's GitHub avatar URL
	AvatarURL         *string `yaml:"avatar"`
	LinkedinURL       *string `yaml:"linkedin"`
	WebsiteURL        *string `yaml:"website"`
	SupportEmail      *string `yaml:"support_email"`
	ContributorStatus *string `yaml:"status"`
}

type contributorProfileReadme struct {
	frontmatter contributorProfileFrontmatter
	namespace   string
	filePath    string
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

	errs := []error{}

	// Can't 100% validate that this is correct without actually sending
	// an email, and especially with some contributors being individual
	// developers, we don't want to do that on every single run of the CI
	// pipeline. Best we can do is verify the general structure
	username, server, ok := strings.Cut(*email, "@")
	if !ok {
		errs = append(errs, fmt.Errorf("email address %q is missing @ symbol", *email))
		return errs
	}

	if username == "" {
		errs = append(errs, fmt.Errorf("email address %q is missing username", *email))
	}

	domain, tld, ok := strings.Cut(server, ".")
	if !ok {
		errs = append(errs, fmt.Errorf("email address %q is missing period for server segment", *email))
		return errs
	}

	if domain == "" {
		errs = append(errs, fmt.Errorf("email address %q is missing domain", *email))
	}
	if tld == "" {
		errs = append(errs, fmt.Errorf("email address %q is missing top-level domain", *email))
	}
	if strings.Contains(*email, "?") {
		errs = append(errs, errors.New("email is not allowed to contain query parameters"))
	}

	return errs
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

	errs := []error{}
	if *avatarURL == "" {
		errs = append(errs, errors.New("avatar URL must be omitted or non-empty string"))
		return errs
	}

	// Have to use .Parse instead of .ParseRequestURI because this is the
	// one field that's allowed to be a relative URL
	if _, err := url.Parse(*avatarURL); err != nil {
		errs = append(errs, fmt.Errorf("URL %q is not a valid relative or absolute URL", *avatarURL))
	}
	if strings.Contains(*avatarURL, "?") {
		errs = append(errs, errors.New("avatar URL is not allowed to contain search parameters"))
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
		errs = append(errs, fmt.Errorf("avatar URL '.%s' does not end in a supported file format: [%s]", fileExtension, strings.Join(supportedAvatarFileFormats, ", ")))
	}

	return errs
}

func validateContributorReadme(rm contributorProfileReadme) []error {
	allErrs := []error{}

	if err := validateContributorDisplayName(rm.frontmatter.DisplayName); err != nil {
		allErrs = append(allErrs, addFilePathToError(rm.filePath, err))
	}
	if err := validateContributorLinkedinURL(rm.frontmatter.LinkedinURL); err != nil {
		allErrs = append(allErrs, addFilePathToError(rm.filePath, err))
	}
	if err := validateContributorWebsite(rm.frontmatter.WebsiteURL); err != nil {
		allErrs = append(allErrs, addFilePathToError(rm.filePath, err))
	}
	if err := validateContributorStatus(rm.frontmatter.ContributorStatus); err != nil {
		allErrs = append(allErrs, addFilePathToError(rm.filePath, err))
	}

	for _, err := range validateContributorSupportEmail(rm.frontmatter.SupportEmail) {
		allErrs = append(allErrs, addFilePathToError(rm.filePath, err))
	}
	for _, err := range validateContributorAvatarURL(rm.frontmatter.AvatarURL) {
		allErrs = append(allErrs, addFilePathToError(rm.filePath, err))
	}

	return allErrs
}

func parseContributorProfile(rm readme) (contributorProfileReadme, error) {
	fm, _, err := separateFrontmatter(rm.rawText)
	if err != nil {
		return contributorProfileReadme{}, fmt.Errorf("%q: failed to parse frontmatter: %v", rm.filePath, err)
	}

	yml := contributorProfileFrontmatter{}
	if err := yaml.Unmarshal([]byte(fm), &yml); err != nil {
		return contributorProfileReadme{}, fmt.Errorf("%q: failed to parse: %v", rm.filePath, err)
	}

	return contributorProfileReadme{
		filePath:    rm.filePath,
		frontmatter: yml,
		namespace:   strings.TrimSuffix(strings.TrimPrefix(rm.filePath, "registry/"), "/README.md"),
	}, nil
}

func parseContributorFiles(readmeEntries []readme) (map[string]contributorProfileReadme, error) {
	profilesByNamespace := map[string]contributorProfileReadme{}
	yamlParsingErrors := []error{}
	for _, rm := range readmeEntries {
		p, err := parseContributorProfile(rm)
		if err != nil {
			yamlParsingErrors = append(yamlParsingErrors, err)
			continue
		}

		if prev, alreadyExists := profilesByNamespace[p.namespace]; alreadyExists {
			yamlParsingErrors = append(yamlParsingErrors, fmt.Errorf("%q: namespace %q conflicts with namespace from %q", p.filePath, p.namespace, prev.filePath))
			continue
		}
		profilesByNamespace[p.namespace] = p
	}
	if len(yamlParsingErrors) != 0 {
		return nil, validationPhaseError{
			phase:  validationPhaseReadmeParsing,
			errors: yamlParsingErrors,
		}
	}

	yamlValidationErrors := []error{}
	for _, p := range profilesByNamespace {
		errors := validateContributorReadme(p)
		if len(errors) > 0 {
			yamlValidationErrors = append(yamlValidationErrors, errors...)
			continue
		}
	}
	if len(yamlValidationErrors) != 0 {
		return nil, validationPhaseError{
			phase:  validationPhaseReadmeParsing,
			errors: yamlValidationErrors,
		}
	}

	return profilesByNamespace, nil
}

func aggregateContributorReadmeFiles() ([]readme, error) {
	dirEntries, err := os.ReadDir(rootRegistryPath)
	if err != nil {
		return nil, err
	}

	allReadmeFiles := []readme{}
	errs := []error{}
	for _, e := range dirEntries {
		dirPath := path.Join(rootRegistryPath, e.Name())
		if !e.IsDir() {
			continue
		}

		readmePath := path.Join(dirPath, "README.md")
		rmBytes, err := os.ReadFile(readmePath)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		allReadmeFiles = append(allReadmeFiles, readme{
			filePath: readmePath,
			rawText:  string(rmBytes),
		})
	}

	if len(errs) != 0 {
		return nil, validationPhaseError{
			phase:  validationPhaseFileLoad,
			errors: errs,
		}
	}

	return allReadmeFiles, nil
}

func validateContributorRelativeUrls(contributors map[string]contributorProfileReadme) error {
	// This function only validates relative avatar URLs for now, but it can be
	// beefed up to validate more in the future
	errs := []error{}

	for _, con := range contributors {
		// If the avatar URL is missing, we'll just assume that the Registry
		// site build step will take care of filling in the data properly
		if con.frontmatter.AvatarURL == nil {
			continue
		}

		isRelativeURL := strings.HasPrefix(*con.frontmatter.AvatarURL, ".") ||
			strings.HasPrefix(*con.frontmatter.AvatarURL, "/")
		if !isRelativeURL {
			continue
		}

		if strings.HasPrefix(*con.frontmatter.AvatarURL, "..") {
			errs = append(errs, fmt.Errorf("%q: relative avatar URLs cannot be placed outside a user's namespaced directory", con.filePath))
			continue
		}

		absolutePath := strings.TrimSuffix(con.filePath, "README.md") +
			*con.frontmatter.AvatarURL
		_, err := os.ReadFile(absolutePath)
		if err != nil {
			errs = append(errs, fmt.Errorf("%q: relative avatar path %q does not point to image in file system", con.filePath, *con.frontmatter.AvatarURL))
		}
	}

	if len(errs) == 0 {
		return nil
	}
	return validationPhaseError{
		phase:  validationPhaseAssetCrossReference,
		errors: errs,
	}
}

func validateAllContributorFiles() error {
	allReadmeFiles, err := aggregateContributorReadmeFiles()
	if err != nil {
		return err
	}

	log.Printf("Processing %d README files\n", len(allReadmeFiles))
	contributors, err := parseContributorFiles(allReadmeFiles)
	if err != nil {
		return err
	}
	log.Printf("Processed %d README files as valid contributor profiles", len(contributors))

	err = validateContributorRelativeUrls(contributors)
	if err != nil {
		return err
	}
	log.Println("All relative URLs for READMEs are valid")

	log.Printf("Processed all READMEs in the %q directory\n", rootRegistryPath)
	return nil
}
