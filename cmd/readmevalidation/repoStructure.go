package main

import (
	"errors"
	"fmt"
	"os"
	"path"
)

func validateCoderResourceDirectory(directoryPath string) []error {
	errs := []error{}

	dir, err := os.Stat(directoryPath)
	if err != nil {
		// It's valid for a specific resource directory not to exist. It's just
		// that if it does exist, it must follow specific rules
		if !errors.Is(err, os.ErrNotExist) {
			errs = append(errs, addFilePathToError(directoryPath, err))
		}
		return errs
	}

	if !dir.IsDir() {
		errs = append(errs, fmt.Errorf("%q: path is not a directory", directoryPath))
		return errs
	}

	files, err := os.ReadDir(directoryPath)
	if err != nil {
		errs = append(errs, fmt.Errorf("%q: %v", directoryPath, err))
		return errs
	}
	for _, f := range files {
		if !f.IsDir() {
			continue
		}

		resourceReadmePath := path.Join(directoryPath, f.Name(), "README.md")
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

		modulesPath := path.Join(dirPath, "modules")
		if errs := validateCoderResourceDirectory(modulesPath); len(errs) != 0 {
			problems = append(problems, errs...)
		}
		templatesPath := path.Join(dirPath, "templates")
		if errs := validateCoderResourceDirectory(templatesPath); len(errs) != 0 {
			problems = append(problems, errs...)
		}
	}

	return problems
}

func validateRepoStructure() error {
	errs := validateRegistryDirectory()
	if len(errs) != 0 {
		return validationPhaseError{
			phase:  validationPhaseFileLoad,
			errors: errs,
		}
	}

	return nil
}
