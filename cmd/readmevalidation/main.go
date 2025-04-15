// This package is for validating all the README files present in the Registry
// directory. The expectation is that each contributor, module, and template
// will have an associated README containing useful metadata. This metadata must
// be validated for correct structure during CI, because the files themselves
// are parsed and rendered as UI as part of the Registry site build step (the
// Registry site itself lives in a separate repo).
package main

import (
	"fmt"
	"log"

	"coder.com/coder-registry/cmd/github"
	"github.com/joho/godotenv"
)

func main() {
	// Do basic setup
	log.Println("Beginning README file validation")
	err := godotenv.Load()
	if err != nil {
		log.Panic(err)
	}
	actorUsername, err := github.ActionsActor()
	if err != nil {
		log.Panic(err)
	}
	baseRef, err := github.BaseRef()
	if err != nil {
		log.Panic(err)
	}
	log.Printf("Using branch %q for validation comparison", baseRef)

	// Retrieve data necessary from the GitHub API to help determine whether
	// certain field changes are allowed
	log.Printf("Using GitHub API to determine what fields can be set by user %q\n", actorUsername)
	client, err := github.NewClient()
	if err != nil {
		log.Panic(err)
	}
	tokenUser, err := client.GetUserFromToken()
	if err != nil {
		log.Panic(err)
	}
	tokenUserStatus, err := client.GetUserOrgStatus("coder", tokenUser.Login)
	if err != nil {
		log.Panic(err)
	}
	var actorOrgStatus github.OrgStatus
	if tokenUserStatus == github.OrgStatusMember {
		actorOrgStatus, err = client.GetUserOrgStatus("coder", actorUsername)
		if err != nil {
			log.Panic(err)
		}
	} else {
		log.Println("Provided API token does not belong to a Coder employee. Some README validation steps will be skipped compared to when they run in CI.")
	}
	fmt.Printf("Script GitHub actor %q has Coder organization status %q\n", actorUsername, actorOrgStatus.String())

	log.Println("Starting README validation")

	// Validate file structure of main README directory
	err = validateRepoStructure()
	if err != nil {
		log.Panic(err)
	}

	// Validate contributor README files
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
	err = validateContributorRelativeUrls(contributors)
	if err != nil {
		log.Panic(err)
	}
	log.Println("All relative URLs for READMEs are valid")
	log.Printf("Processed all READMEs in the %q directory\n", rootRegistryPath)

	// Validate modules

	// Validate templates
}
