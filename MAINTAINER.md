# Maintainer Guide

This guide is for maintainers of the Coder Registry repository. It covers processes and tools that are specific to maintaining the repository, validating contributions, and managing releases.

## Prerequisites

### Required Tools

- **Go** - For README validation
- **Bun** - For running tests
- **Git** - For repository management

### Installing Go

[Navigate to the official Go Installation page](https://go.dev/doc/install), and install the correct version for your operating system.

Once Go has been installed, verify the installation via:

```shell
go version
```

## README Validation

The repository uses Go to validate all README files to ensure they meet the requirements for the Registry website.

### Running README Validation

To validate all README files throughout the entire repo:

```shell
go build ./cmd/readmevalidation && ./readmevalidation
```

The resulting binary is already part of the `.gitignore` file, but you can remove it with:

```shell
rm ./readmevalidation
```

### README Validation Criteria

The validation exists for two reasons:

1. Content accessibility
2. Having content designed in a way that's easy for the Registry site build step to use

#### General README Requirements

- There must be a frontmatter section
- There must be exactly one h1 header, and it must be at the very top, directly below the frontmatter
- The README body (if it exists) must start with an h1 header. No other content (including GitHub-Flavored Markdown alerts) is allowed to be placed above it
- When increasing the level of a header, the header's level must be incremented by one each time
- Any `.hcl` code snippets must be labeled as `.tf` snippets instead

  ```txt
  \`\`\`tf
  Content
  \`\`\`
  ```

#### Namespace (Contributor Profile) Criteria

In addition to the general criteria, all namespace README files must have:

- Frontmatter metadata with support for the following fields:
  - `display_name` (required string) – The name to use when displaying the user profile in the Coder Registry site
  - `bio` (optional string) – A short description of who they are
  - `github` (optional string) – Their GitHub handle
  - `avatar_url` (optional string) – A relative/absolute URL pointing to their avatar for the Registry site
  - `linkedin` (optional string) – A URL pointing to their LinkedIn page
  - `support_email` (optional string) – An email for users to reach them at if they need help with a published module
  - `status` (string union) – If defined, this must be one of `"community"`, `"partner"`, or `"official"`. `"community"` should be used for the majority of external contributions. `"partner"` is for companies who have a formal business partnership with Coder. `"official"` should be used only by Coder employees

- The README body (the content that goes directly below the frontmatter) is allowed to be empty, but if it isn't, it must follow all the rules above

#### Module Criteria

In addition to the general criteria, all module README files must have:

- Frontmatter that describes metadata for the module:
  - `display_name` (required string) – This is the name displayed on the Coder Registry website
  - `description` (required string) – A short description of the module, which is displayed on the Registry website
  - `icon` (required string) – A relative/absolute URL pointing to the icon to display for the module in the Coder Registry website
  - `verified` (optional boolean) – Indicates whether the module has been officially verified by Coder. Please do not set this without approval from a Coder employee
  - `tags` (required string array) – A list of metadata tags to describe the module. Used in the Registry site for search and navigation functionality
  - `maintainer_github` (deprecated string) – The name of the creator of the module. This field exists for backwards compatibility with previous versions of the Registry, but going forward, the value will be inferred from the namespace directory
  - `partner_github` (deprecated string) - The name of any additional creators for a module. This field exists for backwards compatibility with previous versions of the Registry, but should not ever be used going forward

- The following content directly under the h1 header (without another header between them):
  - A description of what the module does
  - A Terraform snippet for letting other users import the functionality

    ```tf
    module "cursor" {
      count    = data.coder_workspace.me.start_count
      source   = "registry.coder.com/coder/cursor/coder"
      version  = "1.0.19"
      agent_id = coder_agent.example.id
    }
    ```

## Release Process

The release process involves the following steps:

### 1. Review and Merge PRs

- Review contributor PRs for code quality, tests, and documentation
- Ensure all automated tests pass
- Verify README validation passes
- Merge approved PRs into the `main` branch

### 2. Prepare Release

After merging to `main`, prepare the release:

- Check out the merge commit:

  ```shell
  git checkout MERGE_COMMIT_ID
  ```

- Create annotated tags for each module that was changed:

  ```shell
  git tag -a "release/$namespace/$module/v$version" -m "Release $namespace/$module v$version"
  ```

- Push the tags to origin:

  ```shell
  git push origin release/$namespace/$module/v$version
  ```

For example, to release version 1.0.14 of the coder/aider module:

```shell
git tag -a "release/coder/aider/v1.0.14" -m "Release coder/aider v1.0.14"
git push origin release/coder/aider/v1.0.14
```

### Version Numbers

Version numbers should follow semantic versioning:

- **Patch version** (1.2.3 → 1.2.4): Bug fixes
- **Minor version** (1.2.3 → 1.3.0): New features, adding inputs, deprecating inputs
- **Major version** (1.2.3 → 2.0.0): Breaking changes (removing inputs, changing input types)

### 3. Publishing to Coder Registry

After tags are pushed, the changes will be published to [registry.coder.com](https://registry.coder.com).

> [!NOTE]
> Some data in registry.coder.com is fetched on demand from this repository's `main` branch. This data should update almost immediately after a release, while other changes will take some time to propagate.

## Testing Infrastructure

### Running All Tests

From the repository root:

```shell
bun test
```

### Running Specific Tests

To run tests for specific modules or patterns:

```shell
bun test -t '<regex_pattern>'
```

### Test Requirements

- All modules must have a `main.test.ts` file
- Tests must use the test utilities from `~test` import
- Tests must validate required variables and successful Terraform apply
- The testing suite requires Docker with `--network=host` capabilities

## Repository Structure Management

### Namespaces

- All modules must be placed within a namespace under `/registry/[namespace]/modules/`
- Each namespace should have a README.md file with contributor profile information
- Namespace names must be unique and lowercase

### Images and Assets

Images can be placed in two locations:

1. In the namespace directory: `/registry/[namespace]/images/`
2. For icons used by multiple modules: `/.icons/`

### Module Structure

Each module must contain:

- `main.tf` - Core Terraform functionality
- `main.test.ts` - Test file for validation
- `README.md` - Documentation with required frontmatter

## Validation Checklist for PRs

When reviewing PRs, ensure:

- [ ] Module follows proper directory structure
- [ ] All required files are present (`main.tf`, `main.test.ts`, `README.md`)
- [ ] README has proper frontmatter with all required fields
- [ ] Tests are implemented and pass
- [ ] Code is properly formatted (`bun run fmt`)
- [ ] README validation passes
- [ ] Module follows Terraform best practices
- [ ] No hardcoded values that should be variables
- [ ] Proper variable descriptions and types

## Common Issues and Solutions

### README Validation Failures

- Check frontmatter syntax (YAML format)
- Ensure h1 header is directly below frontmatter
- Verify all required frontmatter fields are present
- Check that code blocks use `tf` instead of `hcl`

### Test Failures

- Ensure Docker is available with `--network=host` support
- Check that all required variables are defined in tests
- Verify Terraform syntax is valid
- Ensure test imports use `~test` alias correctly

### Module Structure Issues

- Use the `./scripts/new_module.sh` script for consistent structure
- Ensure namespace directory exists
- Check that all file paths are correct

## Maintenance Tasks

### Regular Maintenance

- Monitor for security vulnerabilities in dependencies
- Update test infrastructure as needed
- Review and update documentation
- Monitor Registry website for issues

### Dependency Updates

- Keep Bun dependencies up to date
- Monitor Terraform provider updates
- Update test utilities as needed

### Documentation Updates

- Keep README validation criteria current
- Update examples as the platform evolves
- Maintain contributor guidelines

## Emergency Procedures

### Reverting a Release

If a release needs to be reverted:

1. Delete the problematic tag:
   ```shell
   git tag -d release/$namespace/$module/v$version
   git push origin :refs/tags/release/$namespace/$module/v$version
   ```

2. Create a new patch release with the fix

### Handling Security Issues

1. Immediately remove or disable problematic modules
2. Notify affected users through appropriate channels
3. Work with contributors to address security concerns
4. Document the issue and resolution

## Contact and Escalation

For maintainer-specific questions or issues:

- Internal Coder team channels
- Repository issues for public discussion
- Security email for sensitive issues

Remember: As a maintainer, you're responsible for maintaining the quality and security of the Registry. When in doubt, err on the side of caution and seek additional review. 