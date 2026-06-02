package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
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
func separateSkillsFrontmatter(readmeText string) (frontmatter string, body string, err error) {
	if readmeText == "" {
		return "", "", xerrors.New("README is empty")
	}

	const fence = "---"
	var fmBuilder strings.Builder
	var bodyBuilder strings.Builder
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
			bodyBuilder.WriteString(nextLine)
			bodyBuilder.WriteString("\n")
		} else {
			fmBuilder.WriteString(nextLine)
			fmBuilder.WriteString("\n")
		}
	}
	if fenceCount < 2 {
		return "", "", xerrors.New("README does not have two sets of frontmatter fences")
	}
	if strings.TrimSpace(fmBuilder.String()) == "" {
		return "", "", xerrors.New("readme has frontmatter fences but no frontmatter content")
	}

	return fmBuilder.String(), strings.TrimSpace(bodyBuilder.String()), nil
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
	readmes, err := parseAllCoderSkillsReadmes()
	if err != nil {
		return err
	}

	if len(readmes) == 0 {
		return nil
	}

	if err := validateAllCoderSkillsReadmes(readmes); err != nil {
		return err
	}

	logger.Info(context.Background(), "processed all skills README files", "num_files", len(readmes))
	return nil
}

// parseAllCoderSkillsReadmes walks every registry/<namespace>/skills/README.md
// and returns the parsed structures. Callers can pass the result to the
// offline validator (validateAllCoderSkillsReadmes) and, when network access
// is available, also to the online validator (validateAllCoderSkillsOnline)
// so each README is only read and parsed once per run.
func parseAllCoderSkillsReadmes() ([]coderSkillsReadme, error) {
	allReadmeFiles, err := aggregateSkillsReadmeFiles()
	if err != nil {
		return nil, err
	}

	logger.Info(context.Background(), "processing skills README files", "num_files", len(allReadmeFiles))
	if len(allReadmeFiles) == 0 {
		return nil, nil
	}

	return parseCoderSkillsReadmeFiles(allReadmeFiles)
}

// skillsSourceKey identifies one unique upstream source so the online
// verifier clones a given repo@ref exactly once across all namespaces.
type skillsSourceKey struct {
	repo string // "owner/repo"
	ref  string // resolved ref; defaults to "main" when unspecified.
}

// skillsSourceContent is the result of cloning and walking one upstream
// source repo. Slugs are the directory names under skills/ that contain
// a SKILL.md file.
type skillsSourceContent struct {
	slugs       map[string]bool
	skillMDPath map[string]string // slug -> absolute path to skills/<slug>/SKILL.md
}

// skillMarkdownFrontmatter is the minimal SKILL.md frontmatter shape required
// by the agentskills.io v0.2.0 specification. Both fields are required and
// must be non-empty.
type skillMarkdownFrontmatter struct {
	Name        string `yaml:"name"`
	Description string `yaml:"description"`
}

// validateAllCoderSkillsOnline verifies that every slug declared under
// sources[].skills in a skills README actually exists upstream as
// skills/<slug>/SKILL.md, that each upstream SKILL.md parses with the
// required agentskills.io frontmatter, and that no slug is claimed by more
// than one source within the same namespace.
//
// This function performs network I/O (shallow Git clones). Callers should
// only invoke it when network access is expected to be available.
func validateAllCoderSkillsOnline(readmes []coderSkillsReadme) error {
	if len(readmes) == 0 {
		return nil
	}

	keys, _ := collectUniqueSkillsSources(readmes)
	logger.Info(context.Background(), "verifying upstream skill sources",
		"num_unique_sources", len(keys))

	content := make(map[skillsSourceKey]skillsSourceContent, len(keys))
	var cleanups []func()
	defer func() {
		for _, c := range cleanups {
			c()
		}
	}()

	var errs []error
	for _, k := range keys {
		src, cleanup, err := fetchSkillsSourceContent(k.repo, k.ref)
		if cleanup != nil {
			cleanups = append(cleanups, cleanup)
		}
		if err != nil {
			errs = append(errs, err)
			continue
		}
		content[k] = src
	}

	if len(errs) > 0 {
		return validationPhaseError{phase: validationPhaseUpstream, errors: errs}
	}

	for _, rm := range readmes {
		rErrs := verifyReadmeAgainstSources(rm, content)
		errs = append(errs, rErrs...)
	}

	if len(errs) > 0 {
		return validationPhaseError{phase: validationPhaseUpstream, errors: errs}
	}

	logger.Info(context.Background(), "upstream skill source verification passed",
		"num_files", len(readmes), "num_sources", len(keys))
	return nil
}

// collectUniqueSkillsSources returns every unique repo@ref declared across
// all skills READMEs in deterministic order.
func collectUniqueSkillsSources(readmes []coderSkillsReadme) ([]skillsSourceKey, map[skillsSourceKey]bool) {
	seen := make(map[skillsSourceKey]bool)
	var keys []skillsSourceKey
	for _, rm := range readmes {
		for _, src := range rm.frontmatter.Sources {
			repo, ref, hasRef := strings.Cut(src.Repo, "@")
			if !hasRef || ref == "" {
				ref = "main"
			}
			k := skillsSourceKey{repo: repo, ref: ref}
			if seen[k] {
				continue
			}
			seen[k] = true
			keys = append(keys, k)
		}
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].repo != keys[j].repo {
			return keys[i].repo < keys[j].repo
		}
		return keys[i].ref < keys[j].ref
	})
	return keys, seen
}

// fetchSkillsSourceContent shallow-clones a single upstream source repo at
// the given ref and returns the set of skill slugs found under skills/<slug>/
// that contain a SKILL.md file. The returned cleanup function removes the
// temp clone directory.
//
// Today only branch refs are supported. This matches the behavior of the
// registry-server build pipeline, which clones via plumbing.NewBranchReferenceName.
// When that pipeline grows tag/SHA support, this function should grow it too.
//
// Uses the system git binary instead of a Go Git library so we do not have
// to vendor one for a single shallow clone per source. Every CI runner and
// developer laptop already has git on PATH.
func fetchSkillsSourceContent(repo, ref string) (skillsSourceContent, func(), error) {
	dir, err := os.MkdirTemp("", strings.ReplaceAll(repo, "/", "_")+"_*")
	if err != nil {
		return skillsSourceContent{}, nil, xerrors.Errorf("creating temp dir for %s@%s: %w", repo, ref, err)
	}
	cleanup := func() {
		if rmErr := os.RemoveAll(dir); rmErr != nil {
			logger.Warn(context.Background(), "could not remove temp clone dir",
				"path", dir, "error", rmErr.Error())
		}
	}

	url := "https://github.com/" + repo + ".git"
	cmd := exec.Command("git", "clone", "--depth=1", "--branch", ref, "--single-branch", url, dir)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	if out, err := cmd.CombinedOutput(); err != nil {
		return skillsSourceContent{}, cleanup, xerrors.Errorf("cloning %s@%s: %v: %s", repo, ref, err, strings.TrimSpace(string(out)))
	}

	skillsDir := filepath.Join(dir, "skills")
	entries, err := os.ReadDir(skillsDir)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return skillsSourceContent{
				slugs:       map[string]bool{},
				skillMDPath: map[string]string{},
			}, cleanup, nil
		}
		return skillsSourceContent{}, cleanup, xerrors.Errorf("reading skills directory of %s@%s: %w", repo, ref, err)
	}

	content := skillsSourceContent{
		slugs:       make(map[string]bool, len(entries)),
		skillMDPath: make(map[string]string, len(entries)),
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		skillMD := filepath.Join(skillsDir, e.Name(), "SKILL.md")
		if _, statErr := os.Stat(skillMD); statErr != nil {
			continue
		}
		content.slugs[e.Name()] = true
		content.skillMDPath[e.Name()] = skillMD
	}
	return content, cleanup, nil
}

// verifyReadmeAgainstSources checks one parsed skills README against the
// upstream content already fetched for each declared source.
func verifyReadmeAgainstSources(rm coderSkillsReadme, content map[skillsSourceKey]skillsSourceContent) []error {
	var errs []error

	// Track every slug across every source in this namespace so we can
	// surface duplicates across sources before the registry-server build
	// pipeline silently picks one.
	slugOrigin := make(map[string]string)

	for i, src := range rm.frontmatter.Sources {
		repo, ref, hasRef := strings.Cut(src.Repo, "@")
		if !hasRef || ref == "" {
			ref = "main"
		}
		key := skillsSourceKey{repo: repo, ref: ref}
		upstream, ok := content[key]
		if !ok {
			// fetchSkillsSourceContent already produced an error for this key.
			continue
		}

		for slug := range src.Skills {
			if !upstream.slugs[slug] {
				errs = append(errs, addFilePathToError(rm.filePath,
					xerrors.Errorf("sources[%d].skills[%q]: slug not found upstream at %s/skills/%s/SKILL.md (repo=%s ref=%s)",
						i, slug, repo, slug, repo, ref)))
			}
		}

		for slug := range upstream.slugs {
			origin := fmt.Sprintf("%s@%s", repo, ref)
			if prev, dup := slugOrigin[slug]; dup {
				errs = append(errs, addFilePathToError(rm.filePath,
					xerrors.Errorf("slug %q is provided by multiple sources in the same namespace (%s and %s)",
						slug, prev, origin)))
				continue
			}
			slugOrigin[slug] = origin
		}

		for slug, mdPath := range upstream.skillMDPath {
			for _, fmErr := range validateSkillMarkdownFrontmatter(mdPath) {
				errs = append(errs, addFilePathToError(rm.filePath,
					xerrors.Errorf("sources[%d] %s@%s skill %q: %v", i, repo, ref, slug, fmErr)))
			}
		}
	}

	return errs
}

// validateSkillMarkdownFrontmatter reads a SKILL.md file and confirms its
// YAML frontmatter contains a non-empty name and description per the
// agentskills.io v0.2.0 specification.
func validateSkillMarkdownFrontmatter(absPath string) []error {
	raw, err := os.ReadFile(absPath)
	if err != nil {
		return []error{xerrors.Errorf("could not read SKILL.md: %v", err)}
	}
	fm, _, err := separateSkillsFrontmatter(string(raw))
	if err != nil {
		return []error{xerrors.Errorf("SKILL.md frontmatter parse error: %v", err)}
	}
	var yml skillMarkdownFrontmatter
	if err := yaml.Unmarshal([]byte(fm), &yml); err != nil {
		return []error{xerrors.Errorf("SKILL.md frontmatter YAML invalid: %v", err)}
	}
	var errs []error
	if strings.TrimSpace(yml.Name) == "" {
		errs = append(errs, xerrors.New("SKILL.md is missing required frontmatter field 'name'"))
	}
	if strings.TrimSpace(yml.Description) == "" {
		errs = append(errs, xerrors.New("SKILL.md is missing required frontmatter field 'description'"))
	}
	return errs
}
