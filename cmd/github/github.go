// Package github provides utilities to make it easier to deal with various
// GitHub APIs
package github

import (
	"errors"
	"fmt"
	"os"
)

const (
	actionsActorKey   = "actor"
	actionsBaseRefKey = "base_ref"
	actionsHeadRefKey = "head_ref"
)

// ActionsActor returns the username of the GitHub user who triggered the
// current CI run as part of GitHub Actions. The value must be loaded into the
// env as part of the Github Actions YAML file, or else the function fails.
func ActionsActor() (string, error) {
	username := os.Getenv(actionsActorKey)
	if username == "" {
		return "", fmt.Errorf("value for %q is not in env. Please update the CI script to load the value in during CI", actionsActorKey)
	}
	return username, nil
}

// ActionsRefs returns the name of the head ref and the base ref for current CI
// run, in that order. Both values must be loaded into the env as part of the
// GitHub Actions YAML file, or else the function fails.
func ActionsRefs() (string, string, error) {
	baseRef := os.Getenv(actionsBaseRefKey)
	headRef := os.Getenv(actionsHeadRefKey)
	fmt.Println("Base ref: ", baseRef)
	fmt.Println("Head ref: ", headRef)

	return "", "", errors.New("we ain't ready yet")
}
