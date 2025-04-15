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
	}

	fmt.Printf("actor %q is %s\n", actorUsername, actorOrgStatus.String())

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
