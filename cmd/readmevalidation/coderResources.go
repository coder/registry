package main

import (
	"errors"
	"fmt"
	"net/url"
	"strings"

	"coder.com/coder-registry/cmd/github"
)

type coderResourceFrontmatter struct {
	Description string   `yaml:"description"`
	IconURL     string   `yaml:"icon"`
	DisplayName *string  `yaml:"display_name"`
	Verified    *bool    `yaml:"verified"`
	Tags        []string `yaml:"tags"`
}

// coderResource represents a generic concept for a Terraform resource used to
// help create Coder workspaces. As of 2025-04-15, this encapsulates both
// Coder Modules and Coder Templates. If the newReadmeBody and newFrontmatter
// fields are nil, that represents that the file has been deleted
type coderResource struct {
	name           string
	filePath       string
	newReadmeBody  *string
	oldFrontmatter *coderResourceFrontmatter
	newFrontmatter *coderResourceFrontmatter
	oldIsVerified  bool
	newIsVerified  bool
}

func validateCoderResourceDisplayName(displayName *string) error {
	if displayName == nil {
		return nil
	}

	if *displayName == "" {
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
		strings.HasPrefix(iconURL, "../../../.logos")
	if !isPermittedRelativeURL {
		problems = append(problems, errors.New("relative icon URL must either be scoped to that module's directory, or the top-level /.logos directory"))
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

func validateCoderResourceVerifiedStatus(oldVerified bool, newVerified bool, actorOrgStatus github.OrgStatus) error {
	// If the actor making the changes is an employee of Coder, any changes are
	// assumed to be valid
	if actorOrgStatus == github.OrgStatusMember {
		return nil
	}

	// Right now, because we collapse the omitted/nil case and false together,
	// the only field transition that's allowed is if the verified statuses are
	// exactly the same (which includes the field going from omitted to
	// explicitly false, or vice-versa).
	isPermittedChangeForNonEmployee := oldVerified == newVerified
	if isPermittedChangeForNonEmployee {
		return nil
	}

	return fmt.Errorf("actor with status %q is not allowed to flip verified status from %t to %t", actorOrgStatus.String(), oldVerified, newVerified)
}

// Todo: once we decide on how we want the README frontmatter to be formatted
// for the Embedded Registry work, update this function to validate that the
// correct Terraform code snippets are included in the README and are actually
// valid Terraform. Might also want to validate that each header follows proper
// hierarchy (i.e., not jumping from h1 to h3 because you think it looks nicer)
func validateCoderResourceReadmeBody(body string) error {
	trimmed := strings.TrimSpace(body)
	if !strings.HasPrefix(trimmed, "# ") {
		return errors.New("README body must start with ATX-style h1 header (i.e., \"# \")")
	}
	return nil
}

func validateCoderResourceChanges(resource coderResource, actorOrgStatus github.OrgStatus) []error {
	var problems []error

	if resource.newReadmeBody != nil {
		if err := validateCoderResourceReadmeBody(*resource.newReadmeBody); err != nil {
			problems = append(problems, addFilePathToError(resource.filePath, err))
		}
	}

	if resource.newFrontmatter != nil {
		if err := validateCoderResourceDisplayName(resource.newFrontmatter.DisplayName); err != nil {
			problems = append(problems, addFilePathToError(resource.filePath, err))
		}
		if err := validateCoderResourceDescription(resource.newFrontmatter.Description); err != nil {
			problems = append(problems, addFilePathToError(resource.filePath, err))
		}
		if err := validateCoderResourceTags(resource.newFrontmatter.Tags); err != nil {
			problems = append(problems, addFilePathToError(resource.filePath, err))
		}
		if err := validateCoderResourceVerifiedStatus(resource.oldIsVerified, resource.newIsVerified, actorOrgStatus); err != nil {
			problems = append(problems, addFilePathToError(resource.filePath, err))
		}

		for _, err := range validateCoderResourceIconURL(resource.newFrontmatter.IconURL) {
			problems = append(problems, addFilePathToError(resource.filePath, err))
		}
	}

	return problems
}

func parseCoderResourceFiles(oldReadmeFiles []readme, newReadmeFiles []readme) (map[string]coderResource, error) {
	return nil, nil
}

func validateCoderResourceRelativeUrls(map[string]coderResource) []error {
	return nil
}

func aggregateCoderResourceReadmeFiles() ([]readme, error) {
	return nil, nil
}
