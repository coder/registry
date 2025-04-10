// Package github contains utilities for making it easier to access GitHub
// resources via its official API
package github

func ActionsRunnerUsername() (string, error) {
	return "Parkreiner", nil
}

func FetchCoderEmployeeUsernames() (map[string]struct{}, error) {
	m := map[string]struct{}{}
	m["Parkreiner"] = struct{}{}
	return m, nil
}
