package main

import (
	"errors"
	"fmt"
	"os"
	"path"
)

var supportedResourceTypes = []string{"modules", "templates"}

func validateCoderResourceSubdirectory(dirPath string) []error {
	errs := []error{}

	subDir, err := os.Stat(dirPath)
	if err != nil {
		// It's valid for a specific resource directory not to exist. It's just
		// that if it does exist, it must follow specific rules
		if !errors.Is(err, os.ErrNotExist) {
			errs = append(errs, addFilePathToError(dirPath, err))
		}
		return errs
	}

	if !subDir.IsDir() {
		errs = append(errs, fmt.Errorf("%q: path is not a directory", dirPath))
		return errs
	}

	files, err := os.ReadDir(dirPath)
	if err != nil {
		errs = append(errs, addFilePathToError(dirPath, err))
		return errs
	}
	for _, f := range files {
		// The .coder file is sometimes generated as part of Bun tests. These
		// directories will never be committed to
		if !f.IsDir() || f.Name() == ".coder" {
			continue
		}

		resourceReadmePath := path.Join(dirPath, f.Name(), "README.md")
		_, err := os.Stat(resourceReadmePath)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				errs = append(errs, fmt.Errorf("%q: 'README.md' does not exist", resourceReadmePath))
			} else {
				errs = append(errs, addFilePathToError(resourceReadmePath, err))
			}
		}

		mainTerraformPath := path.Join(dirPath, f.Name(), "main.tf")
		_, err = os.Stat(mainTerraformPath)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				errs = append(errs, fmt.Errorf("%q: 'main.tf' file does not exist", mainTerraformPath))
			} else {
				errs = append(errs, addFilePathToError(mainTerraformPath, err))
			}
		}

	}

	return errs
}

func validateRegistryDirectory() []error {
	userDirs, err := os.ReadDir(rootRegistryPath)
	if err != nil {
		return []error{err}
	}

	allErrs := []error{}
	for _, d := range userDirs {
		dirPath := path.Join(rootRegistryPath, d.Name())
		if !d.IsDir() {
			allErrs = append(allErrs, fmt.Errorf("detected non-directory file %q at base of main Registry directory", dirPath))
			continue
		}

		contributorReadmePath := path.Join(dirPath, "README.md")
		_, err := os.Stat(contributorReadmePath)
		if err != nil {
			allErrs = append(allErrs, err)
		}

		for _, rType := range supportedResourceTypes {
			resourcePath := path.Join(dirPath, rType)
			errs := validateCoderResourceSubdirectory(resourcePath)
			if len(errs) != 0 {
				allErrs = append(allErrs, errs...)
			}
		}
	}

	return allErrs
}

func validateRepoStructure() error {
	var problems []error
	if errs := validateRegistryDirectory(); len(errs) != 0 {
		problems = append(problems, errs...)
	}

	_, err := os.Stat("./.icons")
	if err != nil {
		problems = append(problems, errors.New("missing top-level .icons directory (used for storing reusable Coder resource icons)"))
	}

	if len(problems) != 0 {
		return validationPhaseError{
			phase:  validationPhaseFileStructureValidation,
			errors: problems,
		}
	}
	return nil
}
