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
