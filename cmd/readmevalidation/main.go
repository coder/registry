// This package is for validating all contributors within the main Registry
// directory. It validates that it has nothing but sub-directories, and that
// each sub-directory has a README.md file. Each of those files must then
// describe a specific contributor. The contents of these files will be parsed
// by the Registry site build step, to be displayed in the Registry site's UI.
package main

import (
	"context"
	"os"

	"cdr.dev/slog"
	"cdr.dev/slog/sloggers/sloghuman"
)

var logger = slog.Make(sloghuman.Sink(os.Stdout))

func main() {
	logger.Info(context.Background(), "starting README validation")

	// If there are fundamental problems with how the repo is structured, we can't make any guarantees that any further
	// validations will be relevant or accurate.
	err := validateRepoStructure()
	if err != nil {
		logger.Error(context.Background(), "error when validating the repo structure", "error", err.Error())
		os.Exit(1)
	}

	var errs []error
	err = validateAllContributorFiles()
	if err != nil {
		errs = append(errs, err)
	}
	err = validateAllCoderResourceFilesOfType("modules")
	if err != nil {
		errs = append(errs, err)
	}

	if len(errs) == 0 {
		logger.Info(context.Background(), "processed all READMEs in directory", "dir", rootRegistryPath)
		os.Exit(0)
	}
	for _, err := range errs {
		logger.Error(context.Background(), err.Error())
	}
	os.Exit(1)
}
