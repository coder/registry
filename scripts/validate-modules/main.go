// This package handles validating the READMEs of each module within the main
// Registry directory, as well as any assets that they depend on.
package main

import (
	"fmt"
	"log"
	"net/url"
	"os"
	"path"
	"strings"

	"coder.com/coder-registry/cmd/readme"
	"gopkg.in/yaml.v3"
)

// Todo: Once we have all modules loaded in, see if it's worth switching
// any of the functions here over to goroutines

type moduleFrontmatter struct {
	Description string    `yaml:"description"`
	IconURL     string    `yaml:"icon"`
	DisplayName *string   `yaml:"display_name"`
	Tags        *[]string `yaml:"tags"`
	Verified    *bool     `yaml:"verified"`
}

type moduleReadme struct {
	Frontmatter moduleFrontmatter
	ModuleName  string
	FilePath    string
	Body        string
}

func aggregateModuleReadmeFiles() ([]readme.Readme, error) {
	registryEntries, err := os.ReadDir(readme.RootRegistryPath)
	if err != nil {
		return nil, err
	}

	allReadmeFiles := []readme.Readme{}
	problems := []error{}
	for _, e := range registryEntries {
		if !e.IsDir() {
			continue
		}

		modulesPath := path.Join(readme.RootRegistryPath, e.Name(), "modules")
		modEntries, err := os.ReadDir(modulesPath)
		if err != nil {
			if str := err.Error(); !strings.Contains(str, "no such file or directory") {
				problems = append(problems, err)
			}
			continue
		}

		for _, me := range modEntries {
			if !me.IsDir() {
				continue
			}

			readmePath := path.Join(modulesPath, me.Name(), "README.md")
			rmBytes, err := os.ReadFile(readmePath)
			if err != nil {
				problems = append(problems, err)
				continue
			}
			allReadmeFiles = append(allReadmeFiles, readme.Readme{
				FilePath: readmePath,
				RawText:  string(rmBytes),
			})
		}
	}

	if len(problems) != 0 {
		return nil, readme.ValidationPhaseError{
			Phase:  readme.ValidationPhaseFilesystemRead,
			Errors: problems,
		}
	}

	return allReadmeFiles, nil
}

func validateModuleReadmeFiles(modules map[string]moduleReadme) error {
	// Todo: once we know how we want to have users structure the Terraform code
	// snippet for importing a module, we'll need to verify that the README has
	// that snippet
	validateModuleBody := func(module moduleReadme) []error {
		e := []error{}
		trimmed := strings.TrimSpace(module.Body)

		// Not only is this required for a README to be in 100% valid structure,
		// but we also need the READMEs to be structured this way because of how
		// the Registry build site processes headers
		if !strings.HasPrefix(trimmed, "# ") {
			e = append(
				e,
				fmt.Errorf(
					"%q: README body does not start with ATX-style h1 header (denoted by a single #)",
					module.FilePath,
				),
			)
		}

		return e
	}

	// The verified field is the one field that can't be meaningfully verified
	// in a pure way. There's no point in validating whether the field is the
	// correct type, because the base YAML parsing would've already handled
	// that. And to check whether the field was changed by a Coder employee, you
	// need to make requests to the GitHub API
	validateModuleFrontmatter := func(module moduleReadme) []error {
		problems := []error{}
		fm := module.Frontmatter

		// Display Name
		func() {
			if fm.DisplayName == nil {
				return
			}

			if *fm.DisplayName == "" {
				problems = append(
					problems,
					fmt.Errorf(
						"%q: if defined, display_name must not be empty string",
						module.FilePath,
					),
				)
			}
		}()

		// Description
		if fm.Description == "" {
			problems = append(
				problems,
				fmt.Errorf(
					"%q: frontmatter description cannot be empty",
					module.FilePath,
				),
			)
		}

		// Tags
		func() {
			if fm.Tags == nil {
				return
			}

			// All of these tags are used for the module/template filter
			// controls in the Registry site. Need to make sure they can all be
			// placed in the browser URL without issue
			invalidTags := []string{}
			for _, t := range *fm.Tags {
				if t != url.QueryEscape(t) {
					invalidTags = append(invalidTags, t)
				}
			}
			if len(invalidTags) != 0 {
				problems = append(problems,
					fmt.Errorf(
						"%q: cannot use the following tags as parts of URL filter state: [%s]",
						module.FilePath,
						strings.Join(invalidTags, ", "),
					),
				)
			}
		}()

		return problems
	}

	allErrors := []error{}
	for _, m := range modules {
		allErrors = append(allErrors, validateModuleBody(m)...)
		allErrors = append(allErrors, validateModuleFrontmatter(m)...)
	}
	if len(allErrors) == 0 {
		return nil
	}
	return readme.ValidationPhaseError{
		Phase:  readme.ValidationPhaseReadmeValidation,
		Errors: allErrors,
	}
}

func parseModuleFiles(entries []readme.Readme) (
	map[string]moduleReadme,
	error,
) {
	readmesByName := map[string]moduleReadme{}
	yamlParsingErrors := readme.ValidationPhaseError{
		Phase: readme.ValidationPhaseReadmeParsing,
	}
	for _, rm := range entries {
		fm, body, err := readme.SeparateFrontmatter(rm.RawText)
		if err != nil {
			yamlParsingErrors.Errors = append(
				yamlParsingErrors.Errors,
				fmt.Errorf("failed to parse %q: %v", rm.FilePath, err),
			)
			continue
		}

		yml := moduleFrontmatter{}
		if err := yaml.Unmarshal([]byte(fm), &yml); err != nil {
			yamlParsingErrors.Errors = append(
				yamlParsingErrors.Errors,
				fmt.Errorf("failed to parse %q: %v", rm.FilePath, err),
			)
			continue
		}

		segments := strings.Split(rm.FilePath, "/")
		if len(segments) < 2 {
			yamlParsingErrors.Errors = append(
				yamlParsingErrors.Errors,
				fmt.Errorf("unable to parse main module name from README filepath: %q", rm.FilePath),
			)
			continue
		}
		moduleName := segments[len(segments)-2]

		readmesByName[moduleName] = moduleReadme{
			ModuleName:  moduleName,
			FilePath:    rm.FilePath,
			Frontmatter: yml,
			Body:        body,
		}
	}

	if len(yamlParsingErrors.Errors) == 0 {
		return readmesByName, nil
	}
	return nil, yamlParsingErrors
}

// func validateVerifiedStatusChanges(
// 	modules map[string]moduleReadme,
// 	coderEmployeeUsernames map[string]struct{},
// 	runnerUsername string,
// ) (bool, error) {
// 	return false, nil
// }

func main() {
	log.Println("Starting README validation for modules")
	allReadmeFiles, err := aggregateModuleReadmeFiles()
	if err != nil {
		log.Panic(err)
	}
	if len(allReadmeFiles) == 0 {
		log.Printf("No module files to process")
		return
	}

	log.Printf("Processing %d README files\n", len(allReadmeFiles))
	modules, err := parseModuleFiles(allReadmeFiles)
	if err != nil {
		log.Panic(err)
	}
	log.Printf("Parsed %d module README files", len(modules))

	validationError := validateModuleReadmeFiles(modules)
	if validationError != nil {
		log.Panic(err)
	}
	log.Printf("Validated structure of %d module README files", len(modules))

	// log.Println("Requesting data from GitHub API...")
	// runner, err := github.RunnerUsername()
	// if err != nil {
	// 	log.Panic(err)
	// }
	// coderEmployees, err := github.FetchCoderEmployeeUsernames()
	// if err != nil {
	// 	log.Panic(err)
	// }
	// log.Println("All API data returned successfully.")
	// changesAreValid, err := validateVerifiedStatusChanges(
	// 	modules,
	// 	coderEmployees,
	// 	runner,
	// )
}
