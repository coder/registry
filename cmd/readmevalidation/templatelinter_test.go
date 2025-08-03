package main

import (
	"strings"
	"testing"
)

func TestLintSection(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		section    string
		content    string
		wantErrors int
	}{
		{
			name:    "valid prerequisites section",
			section: "Prerequisites",
			content: `
- AWS CLI v2.0 or later
- Terraform v1.0 or later
- Docker installed locally
Links to installation guides:
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html
`,
			wantErrors: 0,
		},
		{
			name:    "invalid prerequisites - too short",
			section: "Prerequisites",
			content: "- AWS CLI\n",
			wantErrors: 1,
		},
		{
			name:    "valid infrastructure section",
			section: "Infrastructure",
			content: `
This template provisions the following resources:

* EC2 instance (2 CPU, 8GB RAM)
* EBS volume (100GB)
* Security group for workspace access
* IAM role for workspace permissions

All resources are created in your specified AWS region.
`,
			wantErrors: 0,
		},
		{
			name:    "valid variables section with table",
			section: "Variables",
			content: `
| Name | Type | Description | Default |
|------|------|-------------|---------|
| instance_type | string | EC2 instance type | t3.large |
| region | string | AWS region | us-east-1 |
| volume_size | number | Size of root volume in GB | 100 |
`,
			wantErrors: 0,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			
			result := lintSection(tt.section, tt.content)
			
			if len(result.errors) != tt.wantErrors {
				t.Errorf("lintSection() got %d errors, want %d\nerrors: %v",
					len(result.errors), tt.wantErrors, result.errors)
			}
		})
	}
}

func TestLintTemplateReadme(t *testing.T) {
	t.Parallel()

	validReadme := `# AWS Development Template

Complete development environment on AWS.

## Prerequisites
- AWS CLI v2.0 or later
- Terraform v1.0 or later
- Docker installed locally

## Infrastructure
This template provisions:
* EC2 instance (2 CPU, 8GB RAM)
* EBS volume (100GB)
* Security group for workspace access

## Usage
1. Configure AWS credentials
2. Select your region
3. Choose instance type
\`\`\`bash
coder templates push aws-dev
\`\`\`

## Cost and Permissions
Estimated costs:
- t3.large: $0.20/hour
- EBS volume: $10/month

Required permissions:
- ec2:RunInstances
- ec2:CreateTags

## Variables
| Name | Type | Description | Default |
|------|------|-------------|---------|
| instance_type | string | EC2 instance type | t3.large |
| region | string | AWS region | us-east-1 |
`

	results := lintTemplateReadme(validReadme)
	
	// Should have results for all required sections
	wantSections := []string{
		"Prerequisites",
		"Infrastructure",
		"Usage",
		"Cost and Permissions",
		"Variables",
	}
	
	gotSections := make([]string, 0, len(results))
	for _, result := range results {
		gotSections = append(gotSections, result.section)
	}
	
	// Check if all required sections are present
	for _, want := range wantSections {
		found := false
		for _, got := range gotSections {
			if want == got {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("missing required section %q in results", want)
		}
	}
	
	// Check that there are no errors in valid readme
	for _, result := range results {
		if len(result.errors) > 0 {
			t.Errorf("unexpected errors in valid section %q: %v",
				result.section, result.errors)
		}
	}
}
