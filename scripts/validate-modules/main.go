// This package handles validating the READMEs of each module within the main
// Registry directory, as well as any assets that they depend on.
package main

import (
	"fmt"
	"log"
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
			problems = append(problems, err)
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

func parseModuleFiles(entries []readme.Readme) (
	map[string]moduleReadme,
	error,
) {
	readmesByName := map[string]moduleReadme{}
	yamlParsingErrors := readme.ValidationPhaseError{
		Phase: readme.ValidationPhaseYamlParsing,
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

	return readmesByName, nil
}

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
	log.Printf("Verified %d module README files", len(modules))
}
