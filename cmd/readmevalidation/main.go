// This package is for validating all contributors within the main Registry
// directory. It validates that it has nothing but sub-directories, and that
// each sub-directory has a README.md file. Each of those files must then
// describe a specific contributor. The contents of these files will be parsed
// by the Registry site build step, to be displayed in the Registry site's UI.
package main

import (
	"fmt"
	"log"
	"os"
)

func main() {
	log.Println("Starting README validation")

	// If there are fundamental problems with how the repo is structured, we
	// can't make any guarantees that any further validations will be relevant
	// or accurate
	repoErr := validateRepoStructure()
	if repoErr != nil {
		log.Println(repoErr)
		os.Exit(1)
	}

	var errs []error
	err := validateAllContributorFiles()
	if err != nil {
		errs = append(errs, err)
	}
	err = validateAllCoderResourceFilesOfType("modules")
	if err != nil {
		errs = append(errs, err)
	}

	if len(errs) == 0 {
		log.Printf("Processed all READMEs in the %q directory\n", rootRegistryPath)
		os.Exit(0)
	}
	for _, err := range errs {
		fmt.Println(err)
	}
	os.Exit(1)
}
