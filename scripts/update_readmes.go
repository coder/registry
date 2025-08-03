package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"
)

const readmeTemplate = `---
display_name: {{.DisplayName}}
description: {{.Description}}
icon: {{.Icon}}
verified: {{.Verified}}
tags: {{.Tags}}
---

# {{.Title}}

{{.Description}}

## Prerequisites

### Required Tools
- AWS CLI v2.0 or later (installation: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- Terraform v1.0 or later (installation: https://developer.hashicorp.com/terraform/downloads)
{{if .ExtraTools}}{{range .ExtraTools}}
- {{.}}{{end}}{{end}}

### Authentication
{{.AuthInstructions}}

## Infrastructure

This template provisions the following resources:

{{range .Resources}}* {{.}}
{{end}}

Architecture diagram:
` + "```" + `mermaid
graph TD
{{.ArchitectureDiagram}}
` + "```" + `

## Usage

1. Configure credentials:
` + "```" + `bash
{{.SetupCommands}}
` + "```" + `

2. Create the template:
` + "```" + `bash
coder templates create {{.TemplateName}}
` + "```" + `

3. Create a workspace:
` + "```" + `bash
coder create --template {{.TemplateName}} myworkspace
` + "```" + `

Example Terraform configuration:
` + "```" + `hcl
{{.TerraformExample}}
` + "```" + `

## Cost and Permissions

Estimated costs:
{{range .CostEstimates}}* {{.}}
{{end}}

Total: ~{{.TotalCost}}/month

Required permissions:
` + "```" + `json
{{.RequiredPermissions}}
` + "```" + `

Cost optimization tips:
{{range .CostTips}}* {{.}}
{{end}}

## Variables

| Name | Type | Description | Default | Required |
|------|------|-------------|---------|----------|
{{range .Variables}}| {{.Name}} | {{.Type}} | {{.Description}} | {{.Default}} | {{.Required}} |
{{end}}
`

type TemplateData struct {
	DisplayName string
	Description string
	Icon        string
	Verified    bool
	Tags        string
	Title       string

	ExtraTools       []string
	AuthInstructions string

	Resources          []string
	ArchitectureDiagram string

	SetupCommands     string
	TemplateName      string
	TerraformExample  string

	CostEstimates      []string
	TotalCost          string
	RequiredPermissions string
	CostTips           []string

	Variables []Variable
}

type Variable struct {
	Name        string
	Type        string
	Description string
	Default     string
	Required    string
}

func main() {
	// Example usage for aws-linux template
	data := TemplateData{
		DisplayName:  "AWS EC2 (Linux)",
		Description: "Provision AWS EC2 VMs as Coder workspaces",
		Icon:        "../../../../.icons/aws.svg",
		Verified:    true,
		Tags:        "[vm, linux, aws, persistent-vm]",
		Title:       "Remote Development on AWS EC2 VMs (Linux)",

		ExtraTools: []string{
			"Docker (optional)",
			"Git",
		},
		AuthInstructions: "Use AWS credentials file or environment variables. See https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html",

		Resources: []string{
			"EC2 instance (t3.large: 2 vCPU, 8GB RAM)",
			"100GB EBS volume (gp3)",
			"Security group for workspace access",
			"IAM instance profile",
		},
		ArchitectureDiagram: `
    A[Coder Workspace] --> B[EC2 Instance]
    B --> C[EBS Volume]
    B --> D[Security Group]
    B --> E[IAM Profile]`,

		SetupCommands: "aws configure",
		TemplateName:  "aws-linux",
		TerraformExample: `terraform {
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
}`,

		CostEstimates: []string{
			"EC2 t3.large: $0.0832/hour ($60/month)",
			"EBS gp3 100GB: $10/month",
		},
		TotalCost: "$70",
		RequiredPermissions: `{
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
}`,
		CostTips: []string{
			"Use spot instances for dev environments",
			"Enable auto-shutdown during off-hours",
			"Use EBS snapshots for faster startup",
		},

		Variables: []Variable{
			{
				Name:        "region",
				Type:        "string",
				Description: "AWS region",
				Default:     "us-east-1",
				Required:    "Yes",
			},
			{
				Name:        "instance_type",
				Type:        "string",
				Description: "EC2 instance type",
				Default:     "t3.large",
				Required:    "No",
			},
		},
	}

	tmpl, err := template.New("readme").Parse(readmeTemplate)
	if err != nil {
		fmt.Printf("Error parsing template: %v\n", err)
		os.Exit(1)
	}

	// Example: Write to aws-linux template
	path := filepath.Join("registry", "coder", "templates", "aws-linux", "README.md")
	f, err := os.Create(path)
	if err != nil {
		fmt.Printf("Error creating file: %v\n", err)
		os.Exit(1)
	}
	defer f.Close()

	err = tmpl.Execute(f, data)
	if err != nil {
		fmt.Printf("Error executing template: %v\n", err)
		os.Exit(1)
	}
}
