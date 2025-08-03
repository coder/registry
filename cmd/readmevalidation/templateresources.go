package main

import (
	"bufio"
	"strings"

	"golang.org/x/xerrors"
)

// templateResourceFrontmatter extends coderResourceFrontmatter with template-specific fields
type templateResourceFrontmatter struct {
	coderResourceFrontmatter `yaml:",inline"`
	Platform                 string   `yaml:"platform"`
	Requirements            []string `yaml:"requirements"`
	Workload                string   `yaml:"workload"`
}

// templateResourceReadme represents a README specifically for templates
type templateResourceReadme struct {
	coderResourceReadme
	frontmatter templateResourceFrontmatter
}

// templateSection defines required content for a template section
type templateSection struct {
	name         string
	required     bool
	minItems     int
	requirements []string
}

// Required sections and their specific requirements
var templateSections = []templateSection{
	{
		name:     "Prerequisites",
		required: true,
		minItems: 2,
		requirements: []string{
			"Required tools or dependencies with version numbers",
			"Installation instructions with working URLs",
			"Environment setup steps if applicable",
		},
	},
	{
		name:     "Infrastructure",
		required: true,
		minItems: 4,
		requirements: []string{
			"List of provisioned resources with counts",
			"Resource specifications (CPU, RAM, storage, etc.)",
			"Architecture diagram in mermaid or similar format",
			"Network architecture and security considerations",
		},
	},
	{
		name:     "Usage",
		required: true,
		minItems: 4,
		requirements: []string{
			"Step-by-step setup instructions",
			"Example commands with expected output",
			"Complete working Terraform configuration",
			"Troubleshooting guide for common issues",
		},
	},
	{
		name:     "Cost and Permissions",
		required: true,
		minItems: 4,
		requirements: []string{
			"Detailed cost breakdown per resource",
			"Monthly and hourly cost estimates",
			"Required IAM policies or permissions in JSON/YAML",
			"Cost optimization recommendations",
		},
	},
	{
		name:     "Variables",
		required: true,
		minItems: 1,
		requirements: []string{
			"Markdown table with columns: Name, Type, Description, Default, Required",
			"Example values for each variable",
			"Valid options for enum variables",
		},
	},
}

// Get list of required section names
var requiredTemplateSections = func() []string {
	var names []string
	for _, section := range templateSections {
		if section.required {
			names = append(names, section.name)
		}
	}
	return names
}()

func validateTemplatePlatform(platform string) error {
	if platform == "" {
		return xerrors.New("platform field is required for templates")
	}
	
	validPlatforms := []string{
		"aws", "gcp", "azure", "kubernetes", "docker",
		"digitalocean", "openstack", "vsphere", "other",
	}
	
	for _, valid := range validPlatforms {
		if platform == valid {
			return nil
		}
	}
	
	return xerrors.Errorf("invalid platform: %q. Must be one of: %v", platform, validPlatforms)
}

func validateTemplateRequirements(requirements []string) error {
	if len(requirements) == 0 {
		return xerrors.New("requirements field is required for templates")
	}
	return nil
}

func validateTemplateWorkload(workload string) error {
	if workload == "" {
		return xerrors.New("workload field is required for templates")
	}
	
	validWorkloads := []string{
		"development", "data-science", "devops", "security",
		"design", "ml", "other",
	}
	
	for _, valid := range validWorkloads {
		if workload == valid {
			return nil
		}
	}
	
	return xerrors.Errorf("invalid workload: %q. Must be one of: %v", workload, validWorkloads)
}

func validateTemplateSections(body string) []error {
	var errs []error
	
	// Split content into sections
	sections := make(map[string]string)
	var currentSection string
	var sectionContent strings.Builder
	
	scanner := bufio.NewScanner(strings.NewReader(body))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "## ") {
			// Save previous section if it exists
			if currentSection != "" {
				sections[currentSection] = sectionContent.String()
				sectionContent.Reset()
			}
			currentSection = strings.TrimPrefix(line, "## ")
			currentSection = strings.TrimSpace(currentSection)
			continue
		}
		if currentSection != "" {
			sectionContent.WriteString(line + "\n")
		}
	}
	// Save last section
	if currentSection != "" {
		sections[currentSection] = sectionContent.String()
	}
	
	// Validate each required section
	for _, reqSection := range templateSections {
		content, exists := sections[reqSection.name]
		if !exists {
			if reqSection.required {
				errs = append(errs, xerrors.Errorf("missing required section: %q", reqSection.name))
			}
			continue
		}
		
		// Count meaningful items (non-empty lines that aren't just formatting)
		var items []string
		for _, line := range strings.Split(content, "\n") {
			line = strings.TrimSpace(line)
			if line != "" && !strings.HasPrefix(line, "#") && !strings.HasPrefix(line, "---") {
				items = append(items, line)
			}
		}
		
		if len(items) < reqSection.minItems {
			errs = append(errs, xerrors.Errorf("section %q must have at least %d items", 
				reqSection.name, reqSection.minItems))
		}
		
		// Check for required content patterns
		for _, req := range reqSection.requirements {
			found := false
			for _, item := range items {
				if strings.Contains(strings.ToLower(item), strings.ToLower(req)) {
					found = true
					break
				}
			}
			if !found {
				errs = append(errs, xerrors.Errorf("section %q missing required content: %q",
					reqSection.name, req))
			}
		}
		
		// Special validations for specific sections
		switch reqSection.name {
		case "Usage":
			if !strings.Contains(content, "```") {
				errs = append(errs, xerrors.New("Usage section must include code examples"))
			}
			if !strings.Contains(content, "terraform {") {
				errs = append(errs, xerrors.New("Usage section must include Terraform configuration example"))
			}
		case "Variables":
			if !strings.Contains(content, "| Name | Type |") {
				errs = append(errs, xerrors.New("Variables section must include a properly formatted table"))
			}
		case "Infrastructure":
			if !strings.Contains(content, "```mermaid") && !strings.Contains(content, "![") {
				errs = append(errs, xerrors.New("Infrastructure section should include a diagram"))
			}
		}
	}
	
	return errs
}

func validateTemplateReadme(rm templateResourceReadme) []error {
	var errs []error
	
	// First validate base resource requirements
	baseErrs := validateCoderResourceReadme(rm.coderResourceReadme)
	errs = append(errs, baseErrs...)
	
	// Validate template-specific frontmatter
	if err := validateTemplatePlatform(rm.frontmatter.Platform); err != nil {
		errs = append(errs, addFilePathToError(rm.filePath, err))
	}
	if err := validateTemplateRequirements(rm.frontmatter.Requirements); err != nil {
		errs = append(errs, addFilePathToError(rm.filePath, err))
	}
	if err := validateTemplateWorkload(rm.frontmatter.Workload); err != nil {
		errs = append(errs, addFilePathToError(rm.filePath, err))
	}
	
	// Validate template-specific sections
	for _, err := range validateTemplateSections(rm.body) {
		errs = append(errs, addFilePathToError(rm.filePath, err))
	}
	
	return errs
}

func parseTemplateReadme(rm readme) (templateResourceReadme, error) {
	base, err := parseCoderResourceReadme("templates", rm)
	if err != nil {
		return templateResourceReadme{}, err
	}
	
	var frontmatter templateResourceFrontmatter
	if err := yaml.Unmarshal([]byte(rm.frontmatter), &frontmatter); err != nil {
		return templateResourceReadme{}, addFilePathToError(rm.filePath,
			xerrors.Errorf("could not parse YAML frontmatter: %w", err))
	}
	
	return templateResourceReadme{
		coderResourceReadme: base,
		frontmatter:        frontmatter,
	}, nil
}
