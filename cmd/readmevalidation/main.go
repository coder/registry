// This package is for validating all the README files present in the Registry
// directory. The expectation is that each contributor, module, and template
// will have an associated README containing useful metadata. This metadata must
// be validated for correct structure during CI, because the files themselves
// are parsed and rendered as UI as part of the Registry site build step (the
// Registry site itself lives in a separate repo).
package main

import (
	"log"

	"coder.com/coder-registry/cmd/github"
)

func main() {
	username, err := github.ActionsActor()
	if err != nil {
		log.Panic(err)
	}
	log.Printf("running as %q\n", username)
	_, _, err = github.ActionsRefs()
	if err != nil {
		log.Panic(err)
	}

	log.Println("Starting README validation")
	allReadmeFiles, err := aggregateContributorReadmeFiles()
	if err != nil {
		log.Panic(err)
	}

	log.Printf("Processing %d README files\n", len(allReadmeFiles))
	contributors, err := parseContributorFiles(allReadmeFiles)
	log.Printf("Processed %d README files as valid contributor profiles", len(contributors))
	if err != nil {
		log.Panic(err)
	}

	err = validateRelativeUrls(contributors)
	if err != nil {
		log.Panic(err)
	}
	log.Println("All relative URLs for READMEs are valid")

	log.Printf("Processed all READMEs in the %q directory\n", rootRegistryPath)
}
