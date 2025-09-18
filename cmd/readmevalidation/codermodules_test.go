package main

import (
	_ "embed"
	"strings"
	"testing"
)

//go:embed testSamples/sampleReadmeBody.md
var testBody string

// Test bodies extracted for better readability
var (
	validModuleBody = `# Test Module

` + "```tf\n" + `module "test-module" {
  source   = "registry.coder.com/test-namespace/test-module/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
` + "```\n"

	wrongNamespaceBody = `# Test Module

` + "```tf\n" + `module "test-module" {
  source   = "registry.coder.com/wrong-namespace/test-module/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
` + "```\n"

	missingSourceBody = `# Test Module

` + "```tf\n" + `module "test-module" {
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
` + "```\n"

	multipleBlocksValidBody = `# Test Module

` + "```tf\n" + `module "other-module" {
  source   = "registry.coder.com/other/module/coder"
  version  = "1.0.0"
}
` + "```\n" + `
` + "```tf\n" + `module "test-module" {
  source   = "registry.coder.com/test-namespace/test-module/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
` + "```\n"

	multipleBlocksInvalidBody = `# Test Module

` + "```tf\n" + `module "test-module" {
  source   = "registry.coder.com/wrong-namespace/test-module/coder"
  version  = "1.0.0"
}
` + "```\n" + `
` + "```tf\n" + `module "other-module" {
  source   = "registry.coder.com/another-wrong/test-module/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
` + "```\n"
)

func TestValidateCoderResourceReadmeBody(t *testing.T) {
	t.Parallel()

	t.Run("Parses a valid README body with zero issues", func(t *testing.T) {
		t.Parallel()

		errs := validateCoderModuleReadmeBody(testBody)
		for _, e := range errs {
			t.Error(e)
		}
	})
}

func TestValidateModuleSourceURL(t *testing.T) {
	t.Parallel()

	t.Run("Valid source URL format", func(t *testing.T) {
		t.Parallel()

		rm := coderResourceReadme{
			resourceType: "modules",
			filePath:     "registry/test-namespace/modules/test-module/README.md",
			namespace:    "test-namespace",
			resourceName: "test-module",
			body:         validModuleBody,
		}
		errs := validateModuleSourceURL(rm)
		if len(errs) != 0 {
			t.Errorf("Expected no errors, got: %v", errs)
		}
	})

	t.Run("Invalid source URL format - wrong namespace", func(t *testing.T) {
		t.Parallel()

		rm := coderResourceReadme{
			resourceType: "modules",
			filePath:     "registry/test-namespace/modules/test-module/README.md",
			namespace:    "test-namespace",
			resourceName: "test-module",
			body:         wrongNamespaceBody,
		}
		errs := validateModuleSourceURL(rm)
		if len(errs) != 1 {
			t.Errorf("Expected 1 error, got %d: %v", len(errs), errs)
		}
		if !strings.Contains(errs[0].Error(), "incorrect source URL format") {
			t.Errorf("Expected source URL format error, got: %s", errs[0].Error())
		}
	})

	t.Run("Missing source URL", func(t *testing.T) {
		t.Parallel()

		rm := coderResourceReadme{
			resourceType: "modules",
			filePath:     "registry/test-namespace/modules/test-module/README.md",
			namespace:    "test-namespace",
			resourceName: "test-module",
			body:         missingSourceBody,
		}
		errs := validateModuleSourceURL(rm)
		if len(errs) != 1 {
			t.Errorf("Expected 1 error, got %d: %v", len(errs), errs)
		}
		if !strings.Contains(errs[0].Error(), "did not find correct source URL") {
			t.Errorf("Expected missing source URL error, got: %s", errs[0].Error())
		}
	})

	t.Run("Invalid file path format", func(t *testing.T) {
		t.Parallel()

		rm := coderResourceReadme{
			resourceType: "modules",
			filePath:     "invalid/path/format",
			namespace:    "", // Empty because path parsing failed
			resourceName: "", // Empty because path parsing failed
			body:         "# Test Module",
		}
		errs := validateModuleSourceURL(rm)
		if len(errs) != 1 {
			t.Errorf("Expected 1 error, got %d: %v", len(errs), errs)
		}
		if !strings.Contains(errs[0].Error(), "invalid module path format") {
			t.Errorf("Expected path format error, got: %s", errs[0].Error())
		}
	})

	t.Run("Multiple blocks with valid source in second block", func(t *testing.T) {
		t.Parallel()

		rm := coderResourceReadme{
			resourceType: "modules",
			filePath:     "registry/test-namespace/modules/test-module/README.md",
			namespace:    "test-namespace",
			resourceName: "test-module",
			body:         multipleBlocksValidBody,
		}
		errs := validateModuleSourceURL(rm)
		if len(errs) != 0 {
			t.Errorf("Expected no errors, got: %v", errs)
		}
	})

	t.Run("Multiple blocks with incorrect source in second block", func(t *testing.T) {
		t.Parallel()

		rm := coderResourceReadme{
			resourceType: "modules",
			filePath:     "registry/test-namespace/modules/test-module/README.md",
			namespace:    "test-namespace",
			resourceName: "test-module",
			body:         multipleBlocksInvalidBody,
		}
		errs := validateModuleSourceURL(rm)
		if len(errs) != 1 {
			t.Errorf("Expected 1 error, got %d: %v", len(errs), errs)
		}
		if !strings.Contains(errs[0].Error(), "incorrect source URL format") {
			t.Errorf("Expected source URL format error, got: %s", errs[0].Error())
		}
	})
}