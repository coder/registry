package main

import (
	"os"
	"path/filepath"
	"testing"
)

type readmeTestCase struct {
	filePath   string
	shouldPass bool
}

func loadTestCases(t *testing.T, dir string, shouldPass bool) []readmeTestCase {
	t.Helper()
	files, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("Failed to read directory %s: %v", dir, err)
	}

	var testCases []readmeTestCase
	for _, file := range files {
		testCases = append(testCases, readmeTestCase{
			filePath:   filepath.Join(dir, file.Name()),
			shouldPass: shouldPass,
		})
	}
	return testCases
}

func TestValidateModuleReadmes(t *testing.T) {
	t.Parallel()

	testCases := append(
		loadTestCases(t, "testSamples/modules/pass", true),
		loadTestCases(t, "testSamples/modules/fail", false)...,
	)

	for _, tc := range testCases {
		t.Run(tc.filePath, func(t *testing.T) {
			t.Parallel()

			content, err := os.ReadFile(tc.filePath)
			if err != nil {
				t.Fatalf("Failed to read file: %v", err)
			}

			rm := readme{
				filePath: tc.filePath,
				rawText:  string(content),
			}

			resource, errs := parseCoderResourceReadme("modules", rm)
			if len(errs) != 0 {
				if tc.shouldPass {
					for _, e := range errs {
						t.Errorf("Unexpected parsing error: %v", e)
					}
				}
				return
			}

			validationErrs := validateCoderModuleReadme(resource)
			if tc.shouldPass && len(validationErrs) != 0 {
				for _, e := range validationErrs {
					t.Errorf("Unexpected validation error: %v", e)
				}
			} else if !tc.shouldPass && len(validationErrs) == 0 {
				t.Error("Expected validation errors but got none")
			}
		})
	}
}

func TestValidateTemplateReadmes(t *testing.T) {
	t.Parallel()

	testCases := append(
		loadTestCases(t, "testSamples/templates/pass", true),
		loadTestCases(t, "testSamples/templates/fail", false)...,
	)

	for _, tc := range testCases {
		t.Run(tc.filePath, func(t *testing.T) {
			t.Parallel()

			content, err := os.ReadFile(tc.filePath)
			if err != nil {
				t.Fatalf("Failed to read file: %v", err)
			}

			rm := readme{
				filePath: tc.filePath,
				rawText:  string(content),
			}

			resource, errs := parseCoderResourceReadme("templates", rm)
			if len(errs) != 0 {
				if tc.shouldPass {
					for _, e := range errs {
						t.Errorf("Unexpected parsing error: %v", e)
					}
				}
				return
			}

			validationErrs := validateCoderModuleReadme(resource)
			if tc.shouldPass && len(validationErrs) != 0 {
				for _, e := range validationErrs {
					t.Errorf("Unexpected validation error: %v", e)
				}
			} else if !tc.shouldPass && len(validationErrs) == 0 {
				t.Error("Expected validation errors but got none")
			}
		})
	}
}
