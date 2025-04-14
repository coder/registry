// Package github provides utilities to make it easier to deal with various
// GitHub APIs
package github

import (
	"fmt"
	"os"
)

const envActorUsernameKey = "actor"

// ActionsActor returns the username of the GitHub user who triggered the
// current CI run as part of GitHub Actions.The value must be loaded into the
// env as part of the Github Actions script file, or else the function fails.
func ActionsActor() (string, error) {
	username := os.Getenv(envActorUsernameKey)
	if username == "" {
		return "", fmt.Errorf("value for %q is not in env. Please update the CI script to load the value in during CI", envActorUsernameKey)
	}
	return username, nil
}
