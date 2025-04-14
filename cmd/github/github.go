// Package github provides utilities to make it easier to deal with various
// GitHub APIs
package github

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

const defaultGithubAPIRoute = "https://api.github.com/"

const (
	actionsActorKey   = "ACTOR"
	actionsBaseRefKey = "BASE_REF"
	actionsHeadRefKey = "HEAD_REF"
)

const (
	githubAPIURLKey   = "GITHUB_API_URL"
	githubAPITokenKey = "GITHUB_API_TOKEN"
)

// ActionsActor returns the username of the GitHub user who triggered the
// current CI run as part of GitHub Actions. The value must be loaded into the
// env as part of the Github Actions YAML file, or else the function fails.
func ActionsActor() (string, error) {
	username := os.Getenv(actionsActorKey)
	if username == "" {
		return "", fmt.Errorf("value for %q is not in env. If running from CI, please add value via ci.yaml file", actionsActorKey)
	}
	return username, nil
}

// ActionsRefs returns the name of the head ref and the base ref for current CI
// run, in that order. Both values must be loaded into the env as part of the
// GitHub Actions YAML file, or else the function fails.
func ActionsRefs() (string, string, error) {
	baseRef := os.Getenv(actionsBaseRefKey)
	headRef := os.Getenv(actionsHeadRefKey)

	if baseRef == "" && headRef == "" {
		return "", "", fmt.Errorf("values for %q and %q are not in env. If running from CI, please add values via ci.yaml file", actionsHeadRefKey, actionsBaseRefKey)
	} else if headRef == "" {
		return "", "", fmt.Errorf("value for %q is not in env. If running from CI, please add value via ci.yaml file", actionsHeadRefKey)
	} else if baseRef == "" {
		return "", "", fmt.Errorf("value for %q is not in env. If running from CI, please add value via ci.yaml file", actionsBaseRefKey)
	}

	return headRef, baseRef, nil
}

// CoderEmployees represents all members of the Coder GitHub organization. This
// value should not be instantiated from outside the package, and should instead
// be created via one of the package's exported functions.
type CoderEmployees struct {
	// Have map defined as private field to make sure that it can't ever be
	// mutated from an outside package
	_employees map[string]struct{}
}

// IsEmployee takes a GitHub username and indicates whether the matching user is
// a member of the Coder organization
func (ce *CoderEmployees) IsEmployee(username string) bool {
	if ce._employees == nil {
		return false
	}

	_, ok := ce._employees[username]
	return ok
}

// TotalEmployees returns the number of members in the Coder organization
func (ce *CoderEmployees) TotalEmployees() int {
	return len(ce._employees)
}

type ghOrganizationMember struct {
	Login string `json:"login"`
}

type ghRateLimitedRes struct {
	Message string `json:"message"`
}

func parseResponse[V any](b []byte) (V, error) {
	var want V
	var rateLimitedRes ghRateLimitedRes

	if err := json.Unmarshal(b, &rateLimitedRes); err != nil {
		return want, err
	}
	if isRateLimited := strings.Contains(rateLimitedRes.Message, "API rate limit exceeded for "); isRateLimited {
		return want, errors.New("request was rate-limited")
	}
	if err := json.Unmarshal(b, &want); err != nil {
		return want, err
	}

	return want, nil
}

// CoderEmployeeUsernames requests from the GitHub API the list of all usernames
// of people who are employees of Coder.
func CoderEmployeeUsernames() (CoderEmployees, error) {
	apiURL := os.Getenv(githubAPIURLKey)
	if apiURL == "" {
		log.Printf("API URL not set via env key %q. Defaulting to %q\n", githubAPIURLKey, defaultGithubAPIRoute)
		apiURL = defaultGithubAPIRoute
	}
	token := os.Getenv(githubAPITokenKey)
	if token == "" {
		log.Printf("API token not set via env key %q. All requests will be non-authenticated and subject to more aggressive rate limiting", githubAPITokenKey)
	}

	req, err := http.NewRequest("GET", apiURL+"/orgs/coder/members", nil)
	if err != nil {
		return CoderEmployees{}, fmt.Errorf("coder employee names: %v", err)
	}
	if token != "" {
		req.Header.Add("Authorization", "Bearer "+token)
	}

	client := http.Client{Timeout: 5 * time.Second}
	res, err := client.Do(req)
	if err != nil {
		return CoderEmployees{}, fmt.Errorf("coder employee names: %v", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return CoderEmployees{}, fmt.Errorf("coder employee names: got back status code %d", res.StatusCode)
	}

	b, err := io.ReadAll(res.Body)
	if err != nil {
		return CoderEmployees{}, fmt.Errorf("coder employee names: %v", err)
	}
	rawMembers, err := parseResponse[[]ghOrganizationMember](b)
	if err != nil {
		return CoderEmployees{}, fmt.Errorf("coder employee names: %v", err)
	}

	employeesSet := map[string]struct{}{}
	for _, m := range rawMembers {
		employeesSet[m.Login] = struct{}{}
	}
	return CoderEmployees{
		_employees: employeesSet,
	}, nil
}
