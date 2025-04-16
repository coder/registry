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
	"os"
	"sync"

	"coder.com/coder-registry/cmd/github"
	"github.com/go-git/go-git/v5"
	"github.com/go-git/go-git/v5/plumbing"
	"github.com/joho/godotenv"
)

func main() {
	log.Println("Beginning README file validation")

	// Do basic setup
	err := godotenv.Load()
	if err != nil {
		log.Panic(err)
	}
	actorUsername, err := actionsActor()
	if err != nil {
		log.Panic(err)
	}
	ghAPIToken, err := githubAPIToken()
	if err != nil {
		log.Panic(err)
	}

	// Retrieve data necessary from the GitHub API to help determine whether
	// certain field changes are allowed
	log.Printf("Using GitHub API to determine what fields can be set by user %q\n", actorUsername)
	client, err := github.NewClient(github.ClientInit{
		BaseURL:  os.Getenv(githubAPIBaseURLKey),
		APIToken: ghAPIToken,
	})
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

	// Start main validation
	log.Println("Starting README validation")

	// Validate file structure of main README directory. Have to do this
	// synchronously and before everything else, or else there's no way to for
	// the other main validation functions can't make any safe assumptions
	// about where they should look in the repo
	log.Println("Validating directory structure of the README directory")
	err = validateRepoStructure()
	if err != nil {
		log.Panic(err)
	}

	// Set up concurrency for validating each category of README file
	var readmeValidationErrors []error
	errChan := make(chan error, 1)
	doneChan := make(chan struct{})
	wg := sync.WaitGroup{}
	go func() {
		for err := range errChan {
			readmeValidationErrors = append(readmeValidationErrors, err)
		}
		close(doneChan)
	}()

	// Validate contributor README files
	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := validateAllContributors(); err != nil {
			errChan <- fmt.Errorf("contributor validation: %v", err)
		}
	}()

	// Validate modules
	wg.Add(1)
	go func() {
		defer wg.Done()

		refactorLater := func() error {
			baseRefReadmeFiles, err := aggregateCoderResourceReadmeFiles("modules")
			if err != nil {
				return err
			}
			fmt.Printf("------ got %d back\n", len(baseRefReadmeFiles))

			repo, err := git.PlainOpenWithOptions(".", &git.PlainOpenOptions{
				DetectDotGit:          false,
				EnableDotGitCommonDir: false,
			})
			if err != nil {
				return err
			}

			head, err := repo.Head()
			if err != nil {
				return err
			}
			activeBranchName := head.Name().Short()
			fmt.Println("yeah...")

			tree, err := repo.Worktree()
			if err != nil {
				return err
			}
			err = tree.Checkout(&git.CheckoutOptions{
				Branch: plumbing.NewBranchReferenceName(activeBranchName),
				Create: false,
				Force:  false,
				Keep:   true,
			})
			if err != nil {
				return err
			}

			fmt.Println("Got here!")
			files, _ := tree.Filesystem.ReadDir(".")
			for _, f := range files {
				if f.IsDir() {
					fmt.Println(f.Name())
				}
			}

			return nil
		}

		if err := refactorLater(); err != nil {
			errChan <- fmt.Errorf("module validation: %v", err)
		}

	}()

	// Validate templates
	wg.Add(1)
	go func() {
		defer wg.Done()
	}()

	// Clean up and then log errors
	wg.Wait()
	close(errChan)
	<-doneChan
	if len(readmeValidationErrors) == 0 {
		log.Println("All validation was successful")
		return
	}

	fmt.Println("---")
	fmt.Println("Encountered the following problems")
	for _, err := range readmeValidationErrors {
		log.Println(err)
	}
	os.Exit(1)
}
