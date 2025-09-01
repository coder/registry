package main

import (
	_ "embed"
	"testing"
)

//go:embed testSamples/sampleReadmeBody.md
var testBody string

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

		body := "# Test Module\n\n```tf\nmodule \"test-module\" {\n  source   = \"registry.coder.com/test-namespace/test-module/coder\"\n  version  = \"1.0.0\"\n  agent_id = coder_agent.example.id\n}\n```\n"
		filePath := "registry/test-namespace/modules/test-module/README.md"
		errs := validateModuleSourceURL(body, filePath)
		if len(errs) != 0 {
			t.Errorf("Expected no errors, got: %v", errs)
		}
	})

	t.Run("Invalid source URL format - wrong namespace", func(t *testing.T) {
		t.Parallel()

		body := "# Test Module\n\n```tf\nmodule \"test-module\" {\n  source   = \"registry.coder.com/wrong-namespace/test-module/coder\"\n  version  = \"1.0.0\"\n  agent_id = coder_agent.example.id\n}\n```\n"
		filePath := "registry/test-namespace/modules/test-module/README.md"
		errs := validateModuleSourceURL(body, filePath)
		if len(errs) != 1 {
			t.Errorf("Expected 1 error, got %d: %v", len(errs), errs)
		}
		if len(errs) > 0 && !contains(errs[0].Error(), "incorrect source URL format") {
			t.Errorf("Expected source URL format error, got: %s", errs[0].Error())
		}
	})

	t.Run("Missing source URL", func(t *testing.T) {
		t.Parallel()

		body := "# Test Module\n\n```tf\nmodule \"other-module\" {\n  source   = \"registry.coder.com/other/other-module/coder\"\n  version  = \"1.0.0\"\n  agent_id = coder_agent.example.id\n}\n```\n"
		filePath := "registry/test-namespace/modules/test-module/README.md"
		errs := validateModuleSourceURL(body, filePath)
		if len(errs) != 1 {
			t.Errorf("Expected 1 error, got %d: %v", len(errs), errs)
		}
		if len(errs) > 0 && !contains(errs[0].Error(), "did not find correct source URL") {
			t.Errorf("Expected missing source URL error, got: %s", errs[0].Error())
		}
	})

	t.Run("Module name with hyphens vs underscores", func(t *testing.T) {
		t.Parallel()

		body := "# Test Module\n\n```tf\nmodule \"test_module\" {\n  source   = \"registry.coder.com/test-namespace/test-module/coder\"\n  version  = \"1.0.0\"\n  agent_id = coder_agent.example.id\n}\n```\n"
		filePath := "registry/test-namespace/modules/test-module/README.md"
		errs := validateModuleSourceURL(body, filePath)
		if len(errs) != 0 {
			t.Errorf("Expected no errors for hyphen/underscore variation, got: %v", errs)
		}
	})

	t.Run("Invalid file path format", func(t *testing.T) {
		t.Parallel()

		body := "# Test Module"
		filePath := "invalid/path/format"
		errs := validateModuleSourceURL(body, filePath)
		if len(errs) != 1 {
			t.Errorf("Expected 1 error, got %d: %v", len(errs), errs)
		}
		if len(errs) > 0 && !contains(errs[0].Error(), "invalid module path format") {
			t.Errorf("Expected path format error, got: %s", errs[0].Error())
		}
	})
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || (len(s) > len(substr) &&
		(s[:len(substr)] == substr || s[len(s)-len(substr):] == substr ||
			indexOfSubstring(s, substr) >= 0)))
}

func indexOfSubstring(s, substr string) int {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}
