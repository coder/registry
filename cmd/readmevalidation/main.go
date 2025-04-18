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
	err := validateAllContributorFiles()
	if err != nil {
		log.Panic(err)
	}
}
