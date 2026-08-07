package main

import "testing"

func TestValidateNamespaceName(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name       string
		shouldPass bool
	}{
		// Lowercase namespaces are always allowed.
		{name: "coder", shouldPass: true},
		{name: "coder-labs", shouldPass: true},
		{name: "aj0070", shouldPass: true},
		{name: "user123", shouldPass: true},
		{name: "excellencedev", shouldPass: true},
		{name: "iamtaochen", shouldPass: true},

		// Mixed-case namespaces that predate the rule stay allowed.
		{name: "AJ0070", shouldPass: true},
		{name: "BenraouaneSoufiane", shouldPass: true},

		// New mixed-case namespaces are rejected.
		{name: "Coder", shouldPass: false},
		{name: "CoderLabs", shouldPass: false},
		{name: "coder-Labs", shouldPass: false},
		{name: "Excellencedev", shouldPass: false},
		{name: "IamTaoChen", shouldPass: false},

		// Other invalid names are still rejected.
		{name: "", shouldPass: false},
		{name: "-coder", shouldPass: false},
		{name: "coder-", shouldPass: false},
		{name: "coder_labs", shouldPass: false},
		{name: "coder labs", shouldPass: false},
		{name: "coder.labs", shouldPass: false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			err := validateNamespaceName(tc.name)
			if tc.shouldPass && err != nil {
				t.Errorf("expected %q to be a valid namespace name, got error: %v", tc.name, err)
			}
			if !tc.shouldPass && err == nil {
				t.Errorf("expected %q to be an invalid namespace name, got no error", tc.name)
			}
		})
	}
}
