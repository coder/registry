package main

import (
	"errors"
	"fmt"
	"os"
	"path"
)

func validateCoderResourceSubdirectory(dirPath string) []error {
	errs := []error{}

	dir, err := os.Stat(dirPath)
	if err != nil {
		// It's valid for a specific resource directory not to exist. It's just
		// that if it does exist, it must follow specific rules
		if !errors.Is(err, os.ErrNotExist) {
			errs = append(errs, addFilePathToError(dirPath, err))
		}
		return errs
	}

	if !dir.IsDir() {
		errs = append(errs, fmt.Errorf("%q: path is not a directory", dirPath))
		return errs
	}

	files, err := os.ReadDir(dirPath)
	if err != nil {
		errs = append(errs, fmt.Errorf("%q: %v", dirPath, err))
		return errs
	}
	for _, f := range files {
		if !f.IsDir() {
			continue
		}

		resourceReadmePath := path.Join(dirPath, f.Name(), "README.md")
		_, err := os.Stat(resourceReadmePath)
		if err == nil {
			continue
		}

		if errors.Is(err, os.ErrNotExist) {
			errs = append(errs, fmt.Errorf("%q: README file does not exist", resourceReadmePath))
		} else {
			errs = append(errs, addFilePathToError(resourceReadmePath, err))
		}
	}

	return errs
}

func validateRegistryDirectory() []error {
	dirEntries, err := os.ReadDir(rootRegistryPath)
	if err != nil {
		return []error{err}
	}

	problems := []error{}
	for _, e := range dirEntries {
		dirPath := path.Join(rootRegistryPath, e.Name())
		if !e.IsDir() {
			problems = append(problems, fmt.Errorf("detected non-directory file %q at base of main Registry directory", dirPath))
			continue
		}

		readmePath := path.Join(dirPath, "README.md")
		_, err := os.Stat(readmePath)
		if err != nil {
			problems = append(problems, err)
		}

		for _, rType := range supportedResourceTypes {
			resourcePath := path.Join(dirPath, rType)
			if errs := validateCoderResourceSubdirectory(resourcePath); len(errs) != 0 {
				problems = append(problems, errs...)
			}
		}
	}

	return problems
}

func validateRepoStructure() error {
	var problems []error
	if errs := validateRegistryDirectory(); len(errs) != 0 {
		problems = append(problems, errs...)
	}

	_, err := os.Stat("./.logos")
	if err != nil {
		problems = append(problems, err)
	}

	// Todo: figure out what other directories we want to make guarantees for
	// and add them to this function
	if len(problems) != 0 {
		return validationPhaseError{
			phase:  validationPhaseFileStructureValidation,
			errors: problems,
		}
	}
	return nil
}
