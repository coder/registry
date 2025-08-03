package main

import (
	"testing"
)

func TestValidateTemplatePlatform(t *testing.T) {
	t.Parallel()
	
	tests := []struct {
		name     string
		platform string
		wantErr  bool
	}{
		{
			name:     "valid aws platform",
			platform: "aws",
			wantErr:  false,
		},
		{
			name:     "empty platform",
			platform: "",
			wantErr:  true,
		},
		{
			name:     "invalid platform",
			platform: "invalid",
			wantErr:  true,
		},
	}
	
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			err := validateTemplatePlatform(tt.platform)
			if (err != nil) != tt.wantErr {
				t.Errorf("validateTemplatePlatform() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestValidateTemplateRequirements(t *testing.T) {
	t.Parallel()
	
	tests := []struct {
		name         string
		requirements []string
		wantErr     bool
	}{
		{
			name:         "valid requirements",
			requirements: []string{"aws-cli", "docker"},
			wantErr:     false,
		},
		{
			name:         "empty requirements",
			requirements: []string{},
			wantErr:     true,
		},
		{
			name:         "nil requirements",
			requirements: nil,
			wantErr:     true,
		},
	}
	
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			err := validateTemplateRequirements(tt.requirements)
			if (err != nil) != tt.wantErr {
				t.Errorf("validateTemplateRequirements() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestValidateTemplateSections(t *testing.T) {
	t.Parallel()
	
	validReadme := `# AWS Development Template

Complete development environment on AWS.

## Prerequisites
- AWS CLI v2.0 or later
- Terraform v1.0 or later
- Docker installed locally

Links to installation guides:
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html
- Terraform: https://developer.hashicorp.com/terraform/install

## Infrastructure

This template provisions the following resources:

* EC2 instance (2 CPU, 8GB RAM)
* EBS volume (100GB SSD)
* Security group for workspace access
* IAM role for workspace permissions

Architecture diagram:
\`\`\`mermaid
graph TD
    A[Coder Workspace] --> B[EC2 Instance]
    B --> C[EBS Volume]
    B --> D[Security Group]
    B --> E[IAM Role]
\`\`\`

## Usage

1. Configure AWS credentials:
\`\`\`bash
aws configure
\`\`\`

2. Create template:
\`\`\`bash
coder templates create aws-dev
\`\`\`

3. Create workspace:
\`\`\`bash
coder create --template aws-dev mydev
\`\`\`

Example workspace configuration:
\`\`\`hcl
terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = data.coder_parameter.region.value
}

data "coder_parameter" "region" {
  name         = "region"
  display_name = "Region"
  description  = "The region to deploy the workspace in"
  default      = "us-east-1"
  type         = "string"
  mutable      = false
}

resource "coder_agent" "main" {
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    # Install dependencies
    sudo apt-get update
    sudo apt-get install -y docker.io
  EOT  
}
\`\`\`

## Cost and Permissions

Estimated costs:
- EC2 t3.large: $0.0832/hour ($60/month)
- EBS gp3 100GB: $10/month
Total: ~$70/month

Required AWS permissions:
\`\`\`json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "iam:CreateRole",
        "iam:PutRolePolicy"
      ],
      "Resource": "*"
    }
  ]
}
\`\`\`

Cost optimization tips:
- Use spot instances for dev environments
- Enable auto-shutdown during off-hours
- Use EBS snapshots for faster startup

## Variables

| Name | Type | Description | Default | Required |
|------|------|-------------|---------|----------|
| region | string | AWS region | us-east-1 | Yes |
| instance_type | string | EC2 instance type | t3.large | No |
| volume_size | number | Size of root volume in GB | 100 | No |
| additional_tags | map(string) | Additional resource tags | {} | No |
`
	
	missingSection := `# Template Name
Description

## Prerequisites
Required setup

## Infrastructure
Resources used`
	
	noResourceSpecs := strings.ReplaceAll(validReadme, 
		"EC2 instance (2 CPU, 8GB RAM)",
		"EC2 instance")

	noArchDiagram := strings.ReplaceAll(validReadme,
		"\nArchitecture diagram:\n```mermaid\ngraph TD\n    A[Coder Workspace] --> B[EC2 Instance]\n    B --> C[EBS Volume]\n    B --> D[Security Group]\n    B --> E[IAM Role]\n```",
		"")

	noCosts := strings.ReplaceAll(validReadme,
		"EC2 t3.large: $0.0832/hour ($60/month)",
		"EC2 t3.large instance")

	poorVariables := strings.ReplaceAll(validReadme,
		"| Name | Type | Description | Default | Required |\n|------|------|-------------|---------|----------|\n|",
		"Variables:\n- ")

	tests := []struct {
		name    string
		body    string
		wantErr bool
		errMsg  string
	}{
		{
			name:    "valid template readme",
			body:    validReadme,
			wantErr: false,
		},
		{
			name:    "missing required sections",
			body:    missingSection,
			wantErr: true,
			errMsg:  "missing required section",
		},
		{
			name:    "no resource specifications",
			body:    noResourceSpecs,
			wantErr: true,
			errMsg:  "Infrastructure section must include resource specifications",
		},
		{
			name:    "no architecture diagram",
			body:    noArchDiagram,
			wantErr: true,
			errMsg:  "Infrastructure section should include a diagram",
		},
		{
			name:    "missing cost estimates",
			body:    noCosts,
			wantErr: true,
			errMsg:  "Cost and Permissions section must include specific cost estimates",
		},
		{
			name:    "poorly formatted variables",
			body:    poorVariables,
			wantErr: true,
			errMsg:  "Variables section must include a properly formatted table",
		},
	}
	
	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			errs := validateTemplateSections(tt.body)
			if (len(errs) > 0) != tt.wantErr {
				t.Errorf("validateTemplateSections() errors = %v, wantErr %v", errs, tt.wantErr)
			}
		})
	}
}
