package main

import (
	"bufio"
	"context"
	"strings"

	"golang.org/x/xerrors"
)

func validateCoderModuleReadmeBody(body string) []error {
	var errs []error

	trimmed := strings.TrimSpace(body)
	if baseErrs := validateReadmeBody(trimmed); len(baseErrs) != 0 {
		errs = append(errs, baseErrs...)
	}

	foundParagraph := false
	terraformCodeBlockCount := 0
	foundTerraformVersionRef := false

	lineNum := 0
	isInsideCodeBlock := false
	isInsideTerraform := false

	lineScanner := bufio.NewScanner(strings.NewReader(trimmed))
	for lineScanner.Scan() {
		lineNum++
		nextLine := lineScanner.Text()

		// Code assumes that invalid headers would've already been handled by the base validation function, so we don't
		// need to check deeper if the first line isn't an h1.
		if lineNum == 1 {
			if !strings.HasPrefix(nextLine, "# ") {
				break
			}
			continue
		}

		if strings.HasPrefix(nextLine, "```") {
			isInsideCodeBlock = !isInsideCodeBlock
			isInsideTerraform = isInsideCodeBlock && strings.HasPrefix(nextLine, "```tf")
			if isInsideTerraform {
				terraformCodeBlockCount++
			}
			if strings.HasPrefix(nextLine, "```hcl") {
				errs = append(errs, xerrors.New("all hcl code blocks must be converted to tf"))
			}
			continue
		}

		if isInsideCodeBlock {
			if isInsideTerraform {
				foundTerraformVersionRef = foundTerraformVersionRef || terraformVersionRe.MatchString(nextLine)
			}
			continue
		}

		// Code assumes that we can treat this case as the end of the "h1 section" and don't need to process any further lines.
		if lineNum > 1 && strings.HasPrefix(nextLine, "#") {
			break
		}

		// Code assumes that if we've reached this point, the only other options are:
		// (1) empty spaces, (2) paragraphs, (3) HTML, and (4) asset references made via [] syntax.
		trimmedLine := strings.TrimSpace(nextLine)
		isParagraph := trimmedLine != "" && !strings.HasPrefix(trimmedLine, "![") && !strings.HasPrefix(trimmedLine, "<")
		foundParagraph = foundParagraph || isParagraph
	}

	if terraformCodeBlockCount == 0 {
		errs = append(errs, xerrors.New("did not find Terraform code block within h1 section"))
	} else {
		if terraformCodeBlockCount > 1 {
			errs = append(errs, xerrors.New("cannot have more than one Terraform code block in h1 section"))
		}
		if !foundTerraformVersionRef {
			errs = append(errs, xerrors.New("did not find Terraform code block that specifies 'version' field"))
		}
	}
	if !foundParagraph {
		errs = append(errs, xerrors.New("did not find paragraph within h1 section"))
	}
	if isInsideCodeBlock {
		errs = append(errs, xerrors.New("code blocks inside h1 section do not all terminate before end of file"))
	}

	return errs
}

func validateCoderModuleReadme(rm coderResourceReadme) []error {
	var errs []error
	for _, err := range validateCoderModuleReadmeBody(rm.body) {
		errs = append(errs, addFilePathToError(rm.filePath, err))
	}
	if fmErrs := validateCoderResourceFrontmatter("modules", rm.filePath, rm.frontmatter); len(fmErrs) != 0 {
		errs = append(errs, fmErrs...)
	}
	return errs
}

func validateAllCoderModuleReadmes(resources []coderResourceReadme) error {
	var yamlValidationErrors []error
	for _, readme := range resources {
		errs := validateCoderModuleReadme(readme)
		if len(errs) > 0 {
			yamlValidationErrors = append(yamlValidationErrors, errs...)
		}
	}
	if len(yamlValidationErrors) != 0 {
		return validationPhaseError{
			phase:  validationPhaseReadme,
			errors: yamlValidationErrors,
		}
	}
	return nil
}

func validateAllCoderModules() error {
	const resourceType = "modules"
	allReadmeFiles, err := aggregateCoderResourceReadmeFiles(resourceType)
	if err != nil {
		return err
	}

	logger.Info(context.Background(), "processing template README files", "resource_type", resourceType, "num_files", len(allReadmeFiles))
	resources, err := parseCoderResourceReadmeFiles(resourceType, allReadmeFiles)
	if err != nil {
		return err
	}
	err = validateAllCoderModuleReadmes(resources)
	if err != nil {
		return err
	}
	logger.Info(context.Background(), "processed README files as valid Coder resources", "resource_type", resourceType, "num_files", len(resources))

	if err := validateCoderResourceRelativeURLs(resources); err != nil {
		return err
	}
	logger.Info(context.Background(), "all relative URLs for READMEs are valid", "resource_type", resourceType)
	return nil
}
