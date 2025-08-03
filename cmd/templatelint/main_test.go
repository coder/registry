package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGetReadmeFiles(t *testing.T) {
	t.Parallel()

	// Create a temporary test directory
	tmpDir, err := os.MkdirTemp("", "templatelint-test")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	// Create test directory structure
	dirs := []string{
		filepath.Join(tmpDir, "registry/user/templates/template1"),
		filepath.Join(tmpDir, "registry/user/templates/template2"),
		filepath.Join(tmpDir, "registry/user/modules/module1"),
	}

	files := map[string]string{
		filepath.Join(dirs[0], "README.md"): "# Template 1",
		filepath.Join(dirs[1], "README.md"): "# Template 2",
		filepath.Join(dirs[2], "README.md"): "# Module 1",
	}

	// Create directories and files
	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0755); err != nil {
			t.Fatal(err)
		}
	}

	for path, content := range files {
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}

	tests := []struct {
		name      string
		path      string
		wantCount int
		wantErr   bool
	}{
		{
			name:      "single file",
			path:      filepath.Join(dirs[0], "README.md"),
			wantCount: 1,
			wantErr:   false,
		},
		{
			name:      "templates directory",
			path:      filepath.Join(tmpDir, "registry/user/templates"),
			wantCount: 2,
			wantErr:   false,
		},
		{
			name:      "non-existent path",
			path:      filepath.Join(tmpDir, "nonexistent"),
			wantCount: 0,
			wantErr:   true,
		},
		{
			name:      "wrong file name",
			path:      filepath.Join(tmpDir, "wrong.md"),
			wantCount: 0,
			wantErr:   true,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			got, err := getReadmeFiles(tt.path)
			if (err != nil) != tt.wantErr {
				t.Errorf("getReadmeFiles() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && len(got) != tt.wantCount {
				t.Errorf("getReadmeFiles() got %d files, want %d", len(got), tt.wantCount)
			}
		})
	}
}

func TestLintFile(t *testing.T) {
	t.Parallel()

	validContent := `---
display_name: "Valid Template"
description: "A valid template"
icon: "../../../../.icons/platform.svg"
verified: false
tags: ["test"]
platform: "aws"
requirements: ["aws-cli"]
workload: "development"
---

# Valid Template

A valid template description.

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
`

	invalidContent := `---
display_name: "Invalid Template"
---

# Invalid Template

Missing required sections.
`

	// Create temporary test files
	tmpDir, err := os.MkdirTemp("", "templatelint-test")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	validFile := filepath.Join(tmpDir, "valid-README.md")
	invalidFile := filepath.Join(tmpDir, "invalid-README.md")

	if err := os.WriteFile(validFile, []byte(validContent), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(invalidFile, []byte(invalidContent), 0644); err != nil {
		t.Fatal(err)
	}

	tests := []struct {
		name     string
		path     string
		fix      bool
		json     bool
		wantErrs bool
	}{
		{
			name:     "valid readme",
			path:     validFile,
			wantErrs: false,
		},
		{
			name:     "invalid readme",
			path:     invalidFile,
			wantErrs: true,
		},
		{
			name:     "json output",
			path:     validFile,
			json:     true,
			wantErrs: false,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			errs := lintFile(tt.path, tt.fix, tt.json)
			if (len(errs) > 0) != tt.wantErrs {
				t.Errorf("lintFile() got %d errors, wantErrs %v", len(errs), tt.wantErrs)
			}
		})
	}
}
