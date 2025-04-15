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
	"time"
)

const defaultGithubAPIBaseRoute = "https://api.github.com/"

const (
	actionsActorKey   = "CI_ACTOR"
	actionsBaseRefKey = "CI_BASE_REF"
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

// BaseRef returns the name of the base ref for the Git branch that will be
// merged into the main branch.
func BaseRef() (string, error) {
	baseRef := os.Getenv(actionsBaseRefKey)
	if baseRef == "" {
		return "", fmt.Errorf("value for %q is not in env. If running from CI, please add value via ci.yaml file", actionsBaseRefKey)
	}

	return baseRef, nil
}

// Client is a reusable REST client for making requests to the GitHub API.
// It should be instantiated via NewGithubClient
type Client struct {
	baseURL    string
	token      string
	httpClient http.Client
}

// NewClient instantiates a GitHub client
func NewClient() (*Client, error) {
	// Considered letting the user continue on with no token and more aggressive
	// rate-limiting, but from experimentation, the non-authenticated experience
	// hit the rate limits really quickly, and had a lot of restrictions
	apiToken := os.Getenv(githubAPITokenKey)
	if apiToken == "" {
		return nil, fmt.Errorf("missing env variable %q", githubAPITokenKey)
	}

	baseURL := os.Getenv(githubAPIURLKey)
	if baseURL == "" {
		log.Printf("env variable %q is not defined. Falling back to %q\n", githubAPIURLKey, defaultGithubAPIBaseRoute)
		baseURL = defaultGithubAPIBaseRoute
	}

	return &Client{
		baseURL:    baseURL,
		token:      apiToken,
		httpClient: http.Client{Timeout: 10 * time.Second},
	}, nil
}

// User represents a truncated version of the API response from Github's /user
// endpoint.
type User struct {
	Login string `json:"login"`
}

// GetUserFromToken returns the user associated with the loaded API token
func (gc *Client) GetUserFromToken() (User, error) {
	req, err := http.NewRequest("GET", gc.baseURL+"user", nil)
	if err != nil {
		return User{}, err
	}
	if gc.token != "" {
		req.Header.Add("Authorization", "Bearer "+gc.token)
	}

	res, err := gc.httpClient.Do(req)
	if err != nil {
		return User{}, err
	}
	defer res.Body.Close()

	if res.StatusCode == http.StatusUnauthorized {
		return User{}, errors.New("request is not authorized")
	}
	if res.StatusCode == http.StatusForbidden {
		return User{}, errors.New("request is forbidden")
	}

	b, err := io.ReadAll(res.Body)
	if err != nil {
		return User{}, err
	}

	user := User{}
	if err := json.Unmarshal(b, &user); err != nil {
		return User{}, err
	}
	return user, nil
}

// OrgStatus indicates whether a GitHub user is a member of a given organization
type OrgStatus int

var _ fmt.Stringer = OrgStatus(0)

const (
	// OrgStatusIndeterminate indicates when a user's organization status
	// could not be determined. It is the zero value of the OrgStatus type, and
	// any users with this value should be treated as completely untrusted
	OrgStatusIndeterminate = iota
	// OrgStatusNonMember indicates when a user is definitely NOT part of an
	// organization
	OrgStatusNonMember
	// OrgStatusMember indicates when a user is a member of a Github
	// organization
	OrgStatusMember
)

func (s OrgStatus) String() string {
	switch s {
	case OrgStatusMember:
		return "Member"
	case OrgStatusNonMember:
		return "Non-member"
	default:
		return "Indeterminate"
	}
}

// GetUserOrgStatus takes a GitHub username, and checks the GitHub API to see
// whether that member is part of the Coder organization
func (gc *Client) GetUserOrgStatus(org string, username string) (OrgStatus, error) {
	// This API endpoint is really annoying, because it's able to produce false
	// negatives. Any user can be a public member of Coder, a private member of
	// Coder, or a non-member.
	//
	// So if the function returns status 200, you can always trust that. But if
	// it returns any 400 code, that could indicate a few things:
	// 1. The user being checked is not part of the organization, but the user
	//    associated with the token is.
	// 2. The user being checked is a member of the organization, but their
	//    status is private, and the token being used to check belongs to a user
	//    who is not part of the Coder organization.
	// 3. Neither the user being checked nor the user associated with the token
	//    are members of the organization
	//
	// The best option is to make sure that the token being used belongs to a
	// member of the Coder organization
	req, err := http.NewRequest("GET", fmt.Sprintf("%sorgs/%s/%s", gc.baseURL, org, username), nil)
	if err != nil {
		return OrgStatusIndeterminate, err
	}
	if gc.token != "" {
		req.Header.Add("Authorization", "Bearer "+gc.token)
	}

	res, err := gc.httpClient.Do(req)
	if err != nil {
		return OrgStatusIndeterminate, err
	}
	defer res.Body.Close()

	switch res.StatusCode {
	case http.StatusNoContent:
		return OrgStatusMember, nil
	case http.StatusNotFound:
		return OrgStatusNonMember, nil
	default:
		return OrgStatusIndeterminate, nil
	}
}
