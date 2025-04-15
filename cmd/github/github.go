// Package github provides utilities to make it easier to deal with various
// GitHub APIs
package github

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

const defaultGithubAPIBaseRoute = "https://api.github.com/"

// Client is a reusable REST client for making requests to the GitHub API.
// It should be instantiated via NewGithubClient
type Client struct {
	baseURL    string
	token      string
	httpClient http.Client
}

// ClientInit is used to instantiate a new client. If the value of BaseURL is
// not defined, a default value of "https://api.github.com/" is used instead
type ClientInit struct {
	BaseURL  string
	APIToken string
}

// NewClient instantiates a GitHub client. If the baseURL is
func NewClient(init ClientInit) (*Client, error) {
	// Considered letting the user continue on with no token and more aggressive
	// rate-limiting, but from experimentation, the non-authenticated experience
	// hit the rate limits really quickly, and had a lot of restrictions
	apiToken := init.APIToken
	if apiToken == "" {
		return nil, errors.New("API token is missing")
	}

	baseURL := init.BaseURL
	if baseURL == "" {
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
// whether that member is part of the provided organization
func (gc *Client) GetUserOrgStatus(orgName string, username string) (OrgStatus, error) {
	// This API endpoint is really annoying, because it's able to produce false
	// negatives. Any user can be:
	// 1. A public member of an organization
	// 2. A private member of an organization
	// 3. Not a member of an organization
	//
	// So if the function returns status 200, you can always trust that. But if
	// it returns any 400 code, that could indicate a few things:
	// 1. The user associated with the token is a member of the organization,
	//    and the user being checked is not.
	// 2. The user associated with the token is NOT a member of the
	//    organization, and the member being checked is a private member. The
	//    token user will have no way to view the private member's status.
	// 3. Neither the user being checked nor the user associated with the token
	//    are members of the organization.
	//
	// The best option to avoid false positives is to make sure that the token
	// being used belongs to a member of the organization being checked.
	url := fmt.Sprintf("%sorgs/%s/members/%s", gc.baseURL, orgName, username)
	req, err := http.NewRequest("GET", url, nil)
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
