package main

import (
	"encoding/json"
	"fmt"
)

type terraformLifecycleCondition struct {
	// Any terraform expression that evaluates to a boolean
	expression   string
	errorMessage *string
}

type terraformLifecycle struct {
	createBeforeDestroy bool
	preventDestroy      bool
	ignoreChanges       []string
	replaceTriggeredBy  []string
	preCondition        *terraformLifecycleCondition
	postCondition       *terraformLifecycleCondition
}

type terraformForEachKind string

const (
	terraformForEachKindMap terraformForEachKind = "map"
	terraformForEachKindSet terraformForEachKind = "set"
)

type terraformForEach struct {
	kind terraformForEachKind
	// If the kind is "map", all values should be guaranteed to be a definite
	// string for each key. If it's "set", all values should be nil
	values map[string]*string
}

type terraformVariableKind string

const (
	terraformVariableKindString terraformVariableKind = "string"
	terraformVariableKindNumber terraformVariableKind = "number"
	terraformVariableKindBool   terraformVariableKind = "bool"
	terraformVariableKindList   terraformVariableKind = "list"
	terraformVariableKindMap    terraformVariableKind = "map"
	terraformVariableKindSet    terraformVariableKind = "set"
	// This value kind is incredibly rare. It corresponds to any variable with
	// a null value but no defined type
	terraformVariableKindUnknown terraformVariableKind = "unknown"
)

type terraformVariable struct {
	kind  terraformVariableKind
	value any
}

// coderTerraformModule represents the values that can be parsed from a
// Terraform module that are relevant to a Coder deployment. Most of the fields
// are derived from the main Terraform spec, but some additional Coder-specific
// fields are appended, too, for convenience
type coderTerraformModule struct {
	// Corresponds to the optional `lifecycle` metadata field available to all
	// resource types
	Lifecycle *terraformLifecycle `json:"lifecycle"`
	// Corresponds to the optional `for_each` metadata field available to all
	// resource types
	ForEach *terraformForEach `json:"for_each"`
	// Corresponds to the `source` field in a module block
	ModuleSource string `json:"module_source"`
	// Corresponds to the `version` field in Terraform module blocks. Note that
	// while the Terraform spec marks this field as optional, Coder requires
	// that one always be defined.
	Version string `json:"version"`
	// Corresponds to the optional `provider` field in a module block
	Provider *string `json:"provider"`
	// Corresponds to optional `depends_on` field for module blocks
	DependsOn []string `json:"depends_on"`
	// Corresponds to the `count` field for any Terraform resource type. It
	// defines the number of resource instances to create when using Terraform
	// Apply.
	InstanceCount int `json:"instance_count"`
	// Corresponds to `agent_id`` field in a module block. Terraform doesn't
	// have any built-in concept of an agent_id, but it's needed to make a
	// module work with a Coder deployment
	AgentID string `json:"agent_id"`
	// Captures all other arbitrary values defined for a Terraform module block.
	// Note that while Terraform itself has you define all other fields at the
	// same level as the well-known/official fields, they've been isolated into
	// a map for the Go struct definition to improve type-safety
	Values map[string]terraformVariable `json:"values"`
	// The raw Terraform snippet used to derive the coderTerraformModule struct
	SourceCode string `json:"source_code"`
}

var _ json.Marshaler = &coderTerraformModule{}

func (ctmCopy coderTerraformModule) MarshalJSON() ([]byte, error) {
	if ctmCopy.Lifecycle != nil {
		lCopy := &terraformLifecycle{
			createBeforeDestroy: ctmCopy.Lifecycle.createBeforeDestroy,
			preventDestroy:      ctmCopy.Lifecycle.preventDestroy,
			ignoreChanges:       ctmCopy.Lifecycle.ignoreChanges,
			replaceTriggeredBy:  ctmCopy.Lifecycle.replaceTriggeredBy,
			preCondition:        ctmCopy.Lifecycle.preCondition,
			postCondition:       ctmCopy.Lifecycle.postCondition,
		}
		// Make sure that both slices always get serialized as JSON null if
		// they're empty. Serializing as an empty JSON array has no extra
		// semantics
		if len(lCopy.ignoreChanges) == 0 {
			lCopy.ignoreChanges = nil
		}
		if len(lCopy.replaceTriggeredBy) == 0 {
			lCopy.replaceTriggeredBy = nil
		}
		ctmCopy.Lifecycle = lCopy
	}

	if ctmCopy.ForEach != nil {
		feCopy := &terraformForEach{
			kind:   ctmCopy.ForEach.kind,
			values: ctmCopy.ForEach.values,
		}
		// Make sure that the values map is NEVER serialized as JSON null
		if feCopy.values == nil {
			feCopy.values = make(map[string]*string)
		}
		ctmCopy.ForEach = feCopy
	}

	if len(ctmCopy.DependsOn) == 0 {
		ctmCopy.DependsOn = nil
	}

	if ctmCopy.Values == nil {
		ctmCopy.Values = make(map[string]terraformVariable)
	}
	for k, tfValue := range ctmCopy.Values {
		switch tfValue.kind {
		case terraformVariableKindString, terraformVariableKindBool, terraformVariableKindNumber, terraformVariableKindUnknown:
			continue
		case terraformVariableKindSet, terraformVariableKindList:
			recast, ok := tfValue.value.([]any)
			if !ok {
				return nil, fmt.Errorf("unable to process terraform variable %q of kind %q as set/list", k, tfValue.kind)
			}
			if recast == nil {
				ctmCopy.Values[k] = terraformVariable{
					kind:  tfValue.kind,
					value: []any{},
				}
			}
		case terraformVariableKindMap:
			recast, ok := tfValue.value.(map[string]any)
			if !ok {
				return nil, fmt.Errorf("unable to process terraform variable %q of kind %q as map", k, tfValue.kind)
			}
			if recast == nil {
				ctmCopy.Values[k] = terraformVariable{
					kind:  tfValue.kind,
					value: make(map[string]any),
				}
			}
		}
	}

	return json.Marshal(ctmCopy)
}
