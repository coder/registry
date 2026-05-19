package main

import (
	"bufio"
	"context"
	"errors"
	"os"
	"path"
	"regexp"
	"slices"
	"strings"

	"golang.org/x/xerrors"
	"gopkg.in/yaml.v3"
)

// skillsRepoSpecRe matches the "owner/repo" or "owner/repo@ref" format used
// in the skills README sources frontmatter. Owners and repo names allow
// alphanumerics, hyphens, underscores, and dots. Refs allow the same plus
// forward slashes for paths like refs/heads/main.
var skillsRepoSpecRe = regexp.MustCompile(`^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+(@[a-zA-Z0-9_./-]+)?$`)

// skillsIconPrefix is the relative path prefix from a skills README to the
// repo-level .icons directory. The skills README lives at depth 3
// (registry/<namespace>/skills/README.md), so the prefix is three levels up.
// This is distinct from modules and templates, which live at depth 4 and use
// "../../../../.icons/".
const skillsIconPrefix = "../../../.icons/"

// skillOverride holds per-skill presentation metadata defined in the
// registry README. All fields are optional.
type skillOverride struct {
	DisplayName string   `yaml:"display_name"`
	Description string   `yaml:"description"`
	Icon        string   `yaml:"icon"`
	Tags        []string `yaml:"tags"`
}

// skillSource is one entry in the sources list, describing a single source
// repo and optional per-skill overrides.
type skillSource struct {
	Repo   string                   `yaml:"repo"`
	Skills map[string]skillOverride `yaml:"skills"`
}

// coderSkillsFrontmatter is the YAML frontmatter schema for
// registry/<namespace>/skills/README.md.
type coderSkillsFrontmatter struct {
	Icon    string        `yaml:"icon"`
	Sources []skillSource `yaml:"sources"`
}

// supportedSkillsTopLevelKeys lists the keys allowed at the root of the
// skills README frontmatter. Nested keys under sources are validated
// separately because the typed unmarshal handles them.
var supportedSkillsTopLevelKeys = []string{"icon", "sources"}

// coderSkillsReadme represents a parsed skills README file.
type coderSkillsReadme struct {
	filePath    string
	body        string
	frontmatter coderSkillsFrontmatter
}

// separateSkillsFrontmatter is like separateFrontmatter but preserves
// indentation in the frontmatter block. The skills README uses nested YAML
// (per-skill metadata under each source), which the indentation-trimming
// behavior of the shared separateFrontmatter helper destroys.
func separateSkillsFrontmatter(readmeText string) (string, string, error) {
	if readmeText == "" {
		return "", "", xerrors.New("README is empty")
	}

	const fence = "---"
	var fm strings.Builder
	var body strings.Builder
	fenceCount := 0

	lineScanner := bufio.NewScanner(strings.NewReader(strings.TrimSpace(readmeText)))
	for lineScanner.Scan() {
		nextLine := lineScanner.Text()
		if fenceCount < 2 && strings.TrimSpace(nextLine) == fence {
			fenceCount++
			continue
		}
		if fenceCount == 0 {
			break
		}
		if fenceCount >= 2 {
			body.WriteString(nextLine)
			body.WriteString("\n")
		} else {
			fm.WriteString(nextLine)
			fm.WriteString("\n")
		}
	}
	if fenceCount < 2 {
		return "", "", xerrors.New("README does not have two sets of frontmatter fences")
	}
	if strings.TrimSpace(fm.String()) == "" {
		return "", "", xerrors.New("readme has frontmatter fences but no frontmatter content")
	}

	return fm.String(), strings.TrimSpace(body.String()), nil
}

// isPermittedSkillsIconURL validates that an icon URL references the
// repo-level .icons directory using the 3-deep prefix appropriate for
// skills READMEs, and that the file exists on disk.
func isPermittedSkillsIconURL(checkURL string, readmeFilePath string) error {
	if !strings.HasPrefix(checkURL, skillsIconPrefix) {
		return xerrors.Errorf("icon URL %q must reference the top-level .icons directory using %q", checkURL, skillsIconPrefix)
	}

	readmeDir := path.Dir(readmeFilePath)
	resolvedPath := path.Join(readmeDir, checkURL)

	if _, err := os.Stat(resolvedPath); err != nil {
		if os.IsNotExist(err) {
			return xerrors.Errorf("icon file does not exist at resolved path %q (referenced as %q)", resolvedPath, checkURL)
		}
		return xerrors.Errorf("error checking icon file at %q: %v", resolvedPath, err)
	}

	return nil
}

func validateSkillsIconURL(iconURL string, filePath string) []error {
	if iconURL == "" {
		return nil
	}

	var errs []error
	if strings.HasPrefix(iconURL, "http://") || strings.HasPrefix(iconURL, "https://") {
		errs = append(errs, xerrors.Errorf("icon URL must reference the top-level .icons directory, not an absolute URL %q", iconURL))
		return errs
	}

	if err := isPermittedSkillsIconURL(iconURL, filePath); err != nil {
		errs = append(errs, err)
	}
	return errs
}

// validateSkillsTopLevelKeys parses the (indentation-preserved) frontmatter
// as a YAML map and verifies that every top-level key is in the supported
// set. This catches typos like "source:" vs "sources:".
func validateSkillsTopLevelKeys(fm string) []error {
	var rawKeys map[string]any
	if err := yaml.Unmarshal([]byte(fm), &rawKeys); err != nil {
		return []error{xerrors.Errorf("failed to parse frontmatter as YAML map: %v", err)}
	}

	var errs []error
	for key := range rawKeys {
		if !slices.Contains(supportedSkillsTopLevelKeys, key) {
			errs = append(errs, xerrors.Errorf("detected unknown top-level key %q (allowed: %s)", key, strings.Join(supportedSkillsTopLevelKeys, ", ")))
		}
	}
	return errs
}

func validateSkillsSources(sources []skillSource, filePath string) []error {
	if len(sources) == 0 {
		return []error{xerrors.New("at least one source repo is required under 'sources'")}
	}

	var errs []error
	for i, src := range sources {
		if src.Repo == "" {
			errs = append(errs, xerrors.Errorf("sources[%d]: missing required 'repo' field", i))
			continue
		}
		if !skillsRepoSpecRe.MatchString(src.Repo) {
			errs = append(errs, xerrors.Errorf("sources[%d]: repo %q is not a valid owner/repo or owner/repo@ref spec", i, src.Repo))
		}

		for slug, override := range src.Skills {
			if !validNameRe.MatchString(slug) {
				errs = append(errs, xerrors.Errorf("sources[%d]: skill slug %q contains invalid characters (only alphanumeric and hyphens allowed)", i, slug))
			}

			for _, iconErr := range validateSkillsIconURL(override.Icon, filePath) {
				errs = append(errs, xerrors.Errorf("sources[%d].skills[%q]: %v", i, slug, iconErr))
			}

			// validateCoderResourceTags returns an error for nil tags, which is
			// fine for modules/templates that require tags but not for skills
			// where tags are an optional override.
			if override.Tags != nil {
				if err := validateCoderResourceTags(override.Tags); err != nil {
					errs = append(errs, xerrors.Errorf("sources[%d].skills[%q]: %v", i, slug, err))
				}
			}
		}
	}
	return errs
}

func validateCoderSkillsFrontmatter(filePath string, fm coderSkillsFrontmatter) []error {
	var errs []error

	for _, err := range validateSkillsIconURL(fm.Icon, filePath) {
		errs = append(errs, addFilePathToError(filePath, err))
	}

	for _, err := range validateSkillsSources(fm.Sources, filePath) {
		errs = append(errs, addFilePathToError(filePath, err))
	}

	return errs
}

func parseCoderSkillsReadme(rm readme) (coderSkillsReadme, []error) {
	fm, body, err := separateSkillsFrontmatter(rm.rawText)
	if err != nil {
		return coderSkillsReadme{}, []error{xerrors.Errorf("%q: failed to parse frontmatter: %v", rm.filePath, err)}
	}

	keyErrs := validateSkillsTopLevelKeys(fm)
	if len(keyErrs) != 0 {
		var remapped []error
		for _, e := range keyErrs {
			remapped = append(remapped, addFilePathToError(rm.filePath, e))
		}
		return coderSkillsReadme{}, remapped
	}

	yml := coderSkillsFrontmatter{}
	if err := yaml.Unmarshal([]byte(fm), &yml); err != nil {
		return coderSkillsReadme{}, []error{xerrors.Errorf("%q: failed to parse: %v", rm.filePath, err)}
	}

	return coderSkillsReadme{
		filePath:    rm.filePath,
		body:        body,
		frontmatter: yml,
	}, nil
}

func parseCoderSkillsReadmeFiles(rms []readme) ([]coderSkillsReadme, error) {
	var parsed []coderSkillsReadme
	var parsingErrs []error
	for _, rm := range rms {
		p, errs := parseCoderSkillsReadme(rm)
		if len(errs) != 0 {
			parsingErrs = append(parsingErrs, errs...)
			continue
		}
		parsed = append(parsed, p)
	}
	if len(parsingErrs) != 0 {
		return nil, validationPhaseError{
			phase:  validationPhaseReadme,
			errors: parsingErrs,
		}
	}
	return parsed, nil
}

func validateAllCoderSkillsReadmes(readmes []coderSkillsReadme) error {
	var validationErrs []error
	for _, rm := range readmes {
		errs := validateCoderSkillsFrontmatter(rm.filePath, rm.frontmatter)
		if len(errs) > 0 {
			validationErrs = append(validationErrs, errs...)
		}
	}
	if len(validationErrs) != 0 {
		return validationPhaseError{
			phase:  validationPhaseReadme,
			errors: validationErrs,
		}
	}
	return nil
}

// aggregateSkillsReadmeFiles walks registry/<namespace>/skills/README.md
// entries, skipping namespaces that do not have a skills directory.
func aggregateSkillsReadmeFiles() ([]readme, error) {
	namespaceDirs, err := os.ReadDir(rootRegistryPath)
	if err != nil {
		return nil, err
	}

	var allReadmeFiles []readme
	var errs []error
	for _, nDir := range namespaceDirs {
		if !nDir.IsDir() {
			continue
		}

		skillsReadmePath := path.Join(rootRegistryPath, nDir.Name(), "skills", "README.md")
		rmBytes, err := os.ReadFile(skillsReadmePath)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			errs = append(errs, err)
			continue
		}
		allReadmeFiles = append(allReadmeFiles, readme{
			filePath: skillsReadmePath,
			rawText:  string(rmBytes),
		})
	}

	if len(errs) != 0 {
		return nil, validationPhaseError{
			phase:  validationPhaseFile,
			errors: errs,
		}
	}
	return allReadmeFiles, nil
}

func validateAllCoderSkills() error {
	allReadmeFiles, err := aggregateSkillsReadmeFiles()
	if err != nil {
		return err
	}

	logger.Info(context.Background(), "processing skills README files", "num_files", len(allReadmeFiles))
	if len(allReadmeFiles) == 0 {
		return nil
	}

	readmes, err := parseCoderSkillsReadmeFiles(allReadmeFiles)
	if err != nil {
		return err
	}

	if err := validateAllCoderSkillsReadmes(readmes); err != nil {
		return err
	}

	logger.Info(context.Background(), "processed all skills README files", "num_files", len(readmes))
	return nil
}
