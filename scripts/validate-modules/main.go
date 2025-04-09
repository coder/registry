// This package handles validating the READMEs of each module within the main
// Registry directory, as well as any assets that they depend on.
package main

import (
	"log"
	"os"
	"path"

	"coder.com/coder-registry/cmd/readme"
)

/*
Things I need to do:
1. Grab each README file
2.
*/

type moduleFrontmatter struct {
	Description string    `yaml:"description"`
	IconURL     string    `yaml:"icon"`
	DisplayName *string   `yaml:"display_name"`
	Tags        *[]string `yaml:"tags"`
	Verified    *bool     `yaml:"verified"`
}

type moduleFrontmatterWithFilePath struct {
	moduleFrontmatter
	FilePath string
}

func aggregateModuleReadmeFiles() ([]readme.Readme, error) {
	registryEntries, err := os.ReadDir(readme.RootRegistryPath)
	if err != nil {
		return nil, err
	}

	// Todo: Once we have all modules loaded in, see if it's worth switching
	// this function over to use goroutines
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
}
