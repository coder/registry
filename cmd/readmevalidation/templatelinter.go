package main

import (
	"bufio"
	"regexp"
	"strings"

	"golang.org/x/xerrors"
)

// sectionContent defines expected content and validation rules for each section
type sectionContent struct {
	required    bool
	minLines    int
	patterns    []string
	suggestions []string
}

// sectionValidation maps section names to their content requirements
var sectionValidation = map[string]sectionContent{
	"Prerequisites": {
		required: true,
		minLines: 3,
		patterns: []string{
			`^[-*]\s+\w+`, // Bullet points
		},
		suggestions: []string{
			"List all required tools and dependencies",
			"Specify minimum versions if applicable",
			"Include links to installation guides",
		},
	},
	"Infrastructure": {
		required: true,
		minLines: 5,
		patterns: []string{
			`instance|machine|container|cluster|resource`, // Resource types
			`\d+\s*(GB|MB|CPU|core)`,                     // Resource specifications
		},
		suggestions: []string{
			"Detail all infrastructure components",
			"Include resource specifications",
			"List any dependencies between resources",
		},
	},
	"Usage": {
		required: true,
		minLines: 5,
		patterns: []string{
			"```",           // Code blocks
			`^\d+\.\s+\w+`, // Numbered steps
		},
		suggestions: []string{
			"Provide step-by-step instructions",
			"Include code examples",
			"Show common customization options",
		},
	},
	"Cost and Permissions": {
		required: true,
		minLines: 4,
		patterns: []string{
			`\$|\bUSD\b|cost`, // Cost references
			`permission|role|policy|access`, // Permission references
		},
		suggestions: []string{
			"Estimate hourly/monthly costs",
			"List required permissions/roles",
			"Include cost optimization tips",
		},
	},
	"Variables": {
		required: true,
		minLines: 5,
		patterns: []string{
			`^\|\s*\w+\s*\|`, // Table format
			`type\s*=|description\s*=`, // Variable definitions
		},
		suggestions: []string{
			"Document all variables in a table",
			"Include type and description",
			"Provide default values",
		},
	},
}

type lintResult struct {
	section     string
	content     string
	errors      []string
	suggestions []string
}

// lintSection validates the content of a specific section
func lintSection(section, content string) lintResult {
	result := lintResult{
		section: section,
		content: content,
	}

	validation, exists := sectionValidation[section]
	if !exists {
		return result
	}

	// Check minimum length
	lines := strings.Split(strings.TrimSpace(content), "\n")
	if len(lines) < validation.minLines {
		result.errors = append(result.errors,
			xerrors.Errorf("section %q must have at least %d lines of content", 
				section, validation.minLines).Error())
	}

	// Check required patterns
	for _, pattern := range validation.patterns {
		re := regexp.MustCompile(pattern)
		found := false
		for _, line := range lines {
			if re.MatchString(line) {
				found = true
				break
			}
		}
		if !found {
			result.errors = append(result.errors,
				xerrors.Errorf("section %q missing required content matching %q",
					section, pattern).Error())
		}
	}

	// Add improvement suggestions
	result.suggestions = validation.suggestions

	return result
}

// lintTemplateReadme performs detailed content validation of template README sections
func lintTemplateReadme(body string) []lintResult {
	var results []lintResult
	
	currentSection := ""
	var sectionContent strings.Builder
	
	scanner := bufio.NewScanner(strings.NewReader(body))
	for scanner.Scan() {
		line := scanner.Text()
		
		// Check for section headers
		if strings.HasPrefix(line, "## ") {
			// Process previous section if exists
			if currentSection != "" {
				results = append(results, 
					lintSection(currentSection, sectionContent.String()))
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
	
	// Process the last section
	if currentSection != "" {
		results = append(results, 
			lintSection(currentSection, sectionContent.String()))
	}
	
	return results
}

// formatLintResults returns a formatted string of lint results
func formatLintResults(results []lintResult) string {
	var output strings.Builder
	
	output.WriteString("Template README Lint Results:\n\n")
	
	for _, result := range results {
		output.WriteString("## " + result.section + "\n")
		
		if len(result.errors) > 0 {
			output.WriteString("\nErrors:\n")
			for _, err := range result.errors {
				output.WriteString("- " + err + "\n")
			}
		}
		
		if len(result.suggestions) > 0 {
			output.WriteString("\nSuggestions:\n")
			for _, suggestion := range result.suggestions {
				output.WriteString("- " + suggestion + "\n")
			}
		}
		
		output.WriteString("\n")
	}
	
	return output.String()
}
