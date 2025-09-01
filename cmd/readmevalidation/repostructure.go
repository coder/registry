package main

import (
	"errors"
	"os"
	"path"
	"regexp"
	"slices"
	"strings"

	"golang.org/x/xerrors"
)

var supportedUserNameSpaceDirectories = append(supportedResourceTypes, ".images")

// validNameRe validates that names contain only alphanumeric characters and hyphens
var validNameRe = regexp.MustCompile(`^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$`)


// validateCoderResourceSubdirectory validates that the structure of a module or template within a namespace follows all
// expected file conventions
func validateCoderResourceSubdirectory(dirPath string) []error {
	resourceDir, err := os.Stat(dirPath)
	if err != nil {
		// It's valid for a specific resource directory not to exist. It's just that if it does exist, it must follow
		// specific rules.
		if !errors.Is(err, os.ErrNotExist) {
			return []error{addFilePathToError(dirPath, err)}
		}
	}

	if !resourceDir.IsDir() {
		return []error{xerrors.Errorf("%q: path is not a directory", dirPath)}
	}

	files, err := os.ReadDir(dirPath)
	if err != nil {
		return []error{addFilePathToError(dirPath, err)}
	}

	var errs []error
	for _, f := range files {
		// The .coder subdirectories are sometimes generated as part of our Bun tests. These subdirectories will never
		// be committed to the repo, but in the off chance that they don't get cleaned up properly, we want to skip over
		// them.
		if !f.IsDir() || f.Name() == ".coder" {
			continue
		}

		// Validate module/template name
		if !validNameRe.MatchString(f.Name()) {
			errs = append(errs, xerrors.Errorf("%q: name contains invalid characters (only alphanumeric characters and hyphens are allowed)", path.Join(dirPath, f.Name())))
			continue
		}

		resourceReadmePath := path.Join(dirPath, f.Name(), "README.md")
		if _, err := os.Stat(resourceReadmePath); err != nil {
			if errors.Is(err, os.ErrNotExist) {
				errs = append(errs, xerrors.Errorf("%q: 'README.md' does not exist", resourceReadmePath))
			} else {
				errs = append(errs, addFilePathToError(resourceReadmePath, err))
			}
		}

		mainTerraformPath := path.Join(dirPath, f.Name(), "main.tf")
		if _, err := os.Stat(mainTerraformPath); err != nil {
			if errors.Is(err, os.ErrNotExist) {
				errs = append(errs, xerrors.Errorf("%q: 'main.tf' file does not exist", mainTerraformPath))
			} else {
				errs = append(errs, addFilePathToError(mainTerraformPath, err))
			}
		}
	}
	return errs
}

// validateRegistryDirectory validates that the contents of `/registry` follow all expected file conventions. This
// includes the top-level structure of the individual namespace directories.
func validateRegistryDirectory() []error {
	namespaceDirs, err := os.ReadDir(rootRegistryPath)
	if err != nil {
		return []error{err}
	}

	var allErrs []error
	for _, nDir := range namespaceDirs {
		namespacePath := path.Join(rootRegistryPath, nDir.Name())
		if !nDir.IsDir() {
			allErrs = append(allErrs, xerrors.Errorf("detected non-directory file %q at base of main Registry directory", namespacePath))
			continue
		}

		// Validate namespace name
		if !validNameRe.MatchString(nDir.Name()) {
			allErrs = append(allErrs, xerrors.Errorf("%q: namespace name contains invalid characters (only alphanumeric characters and hyphens are allowed)", namespacePath))
			continue
		}

		contributorReadmePath := path.Join(namespacePath, "README.md")
		if _, err := os.Stat(contributorReadmePath); err != nil {
			allErrs = append(allErrs, err)
		}

		files, err := os.ReadDir(namespacePath)
		if err != nil {
			allErrs = append(allErrs, err)
			continue
		}

		for _, f := range files {
			// TODO: Decide if there's anything more formal that we want to ensure about non-directories at the top
			// level of each user namespace.
			if !f.IsDir() {
				continue
			}

			segment := f.Name()
			filePath := path.Join(namespacePath, segment)

			if !slices.Contains(supportedUserNameSpaceDirectories, segment) {
				allErrs = append(allErrs, xerrors.Errorf("%q: only these sub-directories are allowed at top of user namespace: [%s]", filePath, strings.Join(supportedUserNameSpaceDirectories, ", ")))
				continue
			}
			if !slices.Contains(supportedResourceTypes, segment) {
				continue
			}

			if errs := validateCoderResourceSubdirectory(filePath); len(errs) != 0 {
				allErrs = append(allErrs, errs...)
			}
		}
	}

	return allErrs
}

// validateRepoStructure validates that the structure of the repo is "correct enough" to do all necessary validation
// checks. It is NOT an exhaustive validation of the entire repo structure – it only checks the parts of the repo that
// are relevant for the main validation steps
func validateRepoStructure() error {
	var errs []error
	if vrdErrs := validateRegistryDirectory(); len(vrdErrs) != 0 {
		errs = append(errs, vrdErrs...)
	}

	if _, err := os.Stat("./.icons"); err != nil {
		errs = append(errs, xerrors.New("missing top-level .icons directory (used for storing reusable Coder resource icons)"))
	}

	if len(errs) != 0 {
		return validationPhaseError{
			phase:  validationPhaseStructure,
			errors: errs,
		}
	}
	return nil
}
