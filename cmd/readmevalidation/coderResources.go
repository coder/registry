package main

import (
	"errors"
	"fmt"
	"net/url"
	"strings"
)

var supportedResourceTypes = []string{"modules", "templates"}

type coderResourceFrontmatter struct {
	Description string   `yaml:"description"`
	IconURL     string   `yaml:"icon"`
	DisplayName *string  `yaml:"display_name"`
	Verified    *bool    `yaml:"verified"`
	Tags        []string `yaml:"tags"`
}

// coderResourceReadme represents a README describing a Terraform resource used
// to help create Coder workspaces. As of 2025-04-15, this encapsulates both
// Coder Modules and Coder Templates
type coderResourceReadme struct {
	resourceType string
	filePath     string
	body         string
	frontmatter  coderResourceFrontmatter
}

func validateCoderResourceDisplayName(displayName *string) error {
	if displayName != nil && *displayName == "" {
		return errors.New("if defined, display_name must not be empty string")
	}
	return nil
}

func validateCoderResourceDescription(description string) error {
	if description == "" {
		return errors.New("frontmatter description cannot be empty")
	}
	return nil
}

func validateCoderResourceIconURL(iconURL string) []error {
	problems := []error{}

	if iconURL == "" {
		problems = append(problems, errors.New("icon URL cannot be empty"))
		return problems
	}

	isAbsoluteURL := !strings.HasPrefix(iconURL, ".") && !strings.HasPrefix(iconURL, "/")
	if isAbsoluteURL {
		if _, err := url.ParseRequestURI(iconURL); err != nil {
			problems = append(problems, errors.New("absolute icon URL is not correctly formatted"))
		}
		if strings.Contains(iconURL, "?") {
			problems = append(problems, errors.New("icon URLs cannot contain query parameters"))
		}
		return problems
	}

	// Would normally be skittish about having relative paths like this, but it
	// should be safe because we have guarantees about the structure of the
	// repo, and where this logic will run
	isPermittedRelativeURL := strings.HasPrefix(iconURL, "./") ||
		strings.HasPrefix(iconURL, "/") ||
		strings.HasPrefix(iconURL, "../../../../.icons")
	if !isPermittedRelativeURL {
		problems = append(problems, fmt.Errorf("relative icon URL %q must either be scoped to that module's directory, or the top-level /.icons directory (this can usually be done by starting the path with \"../../../.icons\")", iconURL))
	}

	return problems
}

func validateCoderResourceTags(tags []string) error {
	if len(tags) == 0 {
		return nil
	}

	// All of these tags are used for the module/template filter controls in the
	// Registry site. Need to make sure they can all be placed in the browser
	// URL without issue
	invalidTags := []string{}
	for _, t := range tags {
		if t != url.QueryEscape(t) {
			invalidTags = append(invalidTags, t)
		}
	}

	if len(invalidTags) != 0 {
		return fmt.Errorf("found invalid tags (tags that cannot be used for filter state in the Registry website): [%s]", strings.Join(invalidTags, ", "))
	}
	return nil
}

func validateCoderResourceChanges(resource coderResourceReadme) []error {
	var errs []error

	if err := validateReadmeBody(resource.body); err != nil {
		errs = append(errs, addFilePathToError(resource.filePath, err))
	}

	if err := validateCoderResourceDisplayName(resource.frontmatter.DisplayName); err != nil {
		errs = append(errs, addFilePathToError(resource.filePath, err))
	}
	if err := validateCoderResourceDescription(resource.frontmatter.Description); err != nil {
		errs = append(errs, addFilePathToError(resource.filePath, err))
	}
	if err := validateCoderResourceTags(resource.frontmatter.Tags); err != nil {
		errs = append(errs, addFilePathToError(resource.filePath, err))
	}

	for _, err := range validateCoderResourceIconURL(resource.frontmatter.IconURL) {
		errs = append(errs, addFilePathToError(resource.filePath, err))
	}

	return errs
}
