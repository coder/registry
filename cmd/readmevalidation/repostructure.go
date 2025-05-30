package main

import (
	"errors"
	"os"
	"path"
	"slices"
	"strings"

	"golang.org/x/xerrors"
)

var supportedUserNameSpaceDirectories = append(supportedResourceTypes, ".icons", ".images")

func validateCoderResourceSubdirectory(dirPath string) []error {
	errs := []error{}

	subDir, err := os.Stat(dirPath)
	if err != nil {
		// It's valid for a specific resource directory not to exist. It's just
		// that if it does exist, it must follow specific rules.
		if !errors.Is(err, os.ErrNotExist) {
			errs = append(errs, addFilePathToError(dirPath, err))
		}
		return errs
	}

	if !subDir.IsDir() {
		errs = append(errs, xerrors.Errorf("%q: path is not a directory", dirPath))
		return errs
	}

	files, err := os.ReadDir(dirPath)
	if err != nil {
		errs = append(errs, addFilePathToError(dirPath, err))
		return errs
	}
	for _, f := range files {
		// The .coder subdirectories are sometimes generated as part of Bun
		// tests. These subdirectories will never be committed to the repo, but
		// in the off chance that they don't get cleaned up properly, we want to
		// skip over them.
		if !f.IsDir() || f.Name() == ".coder" {
			continue
		}

		resourceReadmePath := path.Join(dirPath, f.Name(), "README.md")
		_, err := os.Stat(resourceReadmePath)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				errs = append(errs, xerrors.Errorf("%q: 'README.md' does not exist", resourceReadmePath))
			} else {
				errs = append(errs, addFilePathToError(resourceReadmePath, err))
			}
		}

		mainTerraformPath := path.Join(dirPath, f.Name(), "main.tf")
		_, err = os.Stat(mainTerraformPath)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				errs = append(errs, xerrors.Errorf("%q: 'main.tf' file does not exist", mainTerraformPath))
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
			allErrs = append(allErrs, xerrors.Errorf("detected non-directory file %q at base of main Registry directory", dirPath))
			continue
		}

		contributorReadmePath := path.Join(dirPath, "README.md")
		_, err := os.Stat(contributorReadmePath)
		if err != nil {
			allErrs = append(allErrs, err)
		}

		files, err := os.ReadDir(dirPath)
		if err != nil {
			allErrs = append(allErrs, err)
			continue
		}

		for _, f := range files {
			// Todo: Decide if there's anything more formal that we want to
			// ensure about non-directories scoped to user namespaces.
			if !f.IsDir() {
				continue
			}

			segment := f.Name()
			filePath := path.Join(dirPath, segment)

			if !slices.Contains(supportedUserNameSpaceDirectories, segment) {
				allErrs = append(allErrs, xerrors.Errorf("%q: only these sub-directories are allowed at top of user namespace: [%s]", filePath, strings.Join(supportedUserNameSpaceDirectories, ", ")))
				continue
			}

			if slices.Contains(supportedResourceTypes, segment) {
				errs := validateCoderResourceSubdirectory(filePath)
				if len(errs) != 0 {
					allErrs = append(allErrs, errs...)
				}
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
		problems = append(problems, xerrors.New("missing top-level .icons directory (used for storing reusable Coder resource icons)"))
	}

	if len(problems) != 0 {
		return validationPhaseError{
			phase:  validationPhaseFileStructureValidation,
			errors: problems,
		}
	}
	return nil
}
