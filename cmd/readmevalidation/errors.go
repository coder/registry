package main

import "fmt"

// validationPhaseError represents an error that occurred during a specific
// phase of README validation. It should be used to collect ALL validation
// errors that happened during a specific phase, rather than the first one
// encountered.
type validationPhaseError struct {
	phase  validationPhase
	errors []error
}

var _ error = validationPhaseError{}

func (vpe validationPhaseError) Error() string {
	msg := fmt.Sprintf("Error during %q phase of README validation:", vpe.phase)
	for _, e := range vpe.errors {
		msg += fmt.Sprintf("\n- %v", e)
	}
	msg += "\n"

	return msg
}

func addFilePathToError(filePath string, err error) error {
	return fmt.Errorf("%q: %v", filePath, err)
}
