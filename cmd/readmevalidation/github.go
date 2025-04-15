package main

import (
	"fmt"
	"os"
)

const actionsActorKey = "CI_ACTOR"

const (
	githubAPIBaseURLKey = "GITHUB_API_URL"
	githubAPITokenKey   = "GITHUB_API_TOKEN"
)

// actionsActor returns the username of the GitHub user who triggered the
// current CI run as part of GitHub Actions. It is expected that this value be
// set using a local .env file in local development, and set via GitHub Actions
// context during CI.
func actionsActor() (string, error) {
	username := os.Getenv(actionsActorKey)
	if username == "" {
		return "", fmt.Errorf("value for %q is not in env. If running from CI, please add value via ci.yaml file", actionsActorKey)
	}
	return username, nil
}

func githubAPIToken() (string, error) {
	token := os.Getenv(githubAPITokenKey)
	if token == "" {
		return "", fmt.Errorf("value for %q is not in env. If running from CI, please add value via ci.yaml file", githubAPITokenKey)
	}
	return token, nil
}
