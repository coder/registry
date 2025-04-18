// This package is for validating all contributors within the main Registry
// directory. It validates that it has nothing but sub-directories, and that
// each sub-directory has a README.md file. Each of those files must then
// describe a specific contributor. The contents of these files will be parsed
// by the Registry site build step, to be displayed in the Registry site's UI.
package main

import (
	"log"
)

func main() {
	log.Println("Starting README validation")
	allReadmeFiles, err := aggregateContributorReadmeFiles()
	if err != nil {
		log.Panic(err)
	}

	log.Printf("Processing %d README files\n", len(allReadmeFiles))
	contributors, err := parseContributorFiles(allReadmeFiles)
	log.Printf(
		"Processed %d README files as valid contributor profiles",
		len(contributors),
	)
	if err != nil {
		log.Panic(err)
	}

	err = validateRelativeUrls(contributors)
	if err != nil {
		log.Panic(err)
	}
	log.Println("All relative URLs for READMEs are valid")

	log.Printf(
		"Processed all READMEs in the %q directory\n",
		rootRegistryPath,
	)
}
