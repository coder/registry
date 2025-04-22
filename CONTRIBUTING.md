# Contributing

## Getting started

This repo uses two main runtimes to verify the correctness of a module/template before it is published:

- [Bun](https://bun.sh/) – Used to run tests for each module/template to validate overall functionality and correctness of Terraform output
- [Go](https://go.dev/) – Used to validate all README files in the directory

### Installing Bun

To install Bun, you can run this command on Linux/MacOS:

```shell
curl -fsSL https://bun.sh/install | bash
```

Or this command on Windows:

```shell
powershell -c "irm bun.sh/install.ps1 | iex"
```

Follow the instructions to ensure that Bun is available globally. Once Bun is installed, install all necessary dependencies from the root of the repo:

Via NPM:

```shell
npm i
```

Via PNPM:

```shell
pnpm i
```

This repo does not support Yarn.

### Installing Go (optional)

This step can be skipped if you are not working on any of the README validation logic. The validation will still run as part of CI.

[Navigate to the official Go Installation page](https://go.dev/doc/install), and install the correct version for your operating system.

Once Go has been installed, verify the installation via:

```shell
go version
```

### Adding a new module/template (coming soon)

Once Bun (and possibly Go) have been installed, clone this repository. From there, you can run this script to make it easier to start contributing a new module or template:

```shell
./new.sh NAME_OF_NEW_MODULE
```

You can also create the correct module/template files manually.

## Testing a Module

> [!IMPORTANT]
> It is the responsibility of the module author to implement tests for every new module they wish to contribute. It falls to the author to test the module locally before submitting a PR.

All general-purpose test helpers for validating Terraform can be found in the top-level `/testing` directory. The helpers run `terraform apply` on modules that use variables, testing the script output against containers.

> [!NOTE]
> The testing suite must be able to run docker containers with the `--network=host` flag. This typically requires running the tests on Linux as this flag does not apply to Docker Desktop for MacOS and Windows. MacOS users can work around this by using something like [colima](https://github.com/abiosoft/colima) or [Orbstack](https://orbstack.dev/) instead of Docker Desktop.

You can reference the existing `*.test.ts` files to get an idea for how to set up tests.

You can run all tests by running this command:

```shell
bun test
```

Note that tests can take some time to run, so you probably don't want to be running this as part of your development loop.

To run specific tests, you can use the `-t` flag, which accepts a filepath regex:

```shell
bun test -t '<regex_pattern>'
```

To ensure that the module runs predictably in local development, you can update the Terraform source as follows:

```tf
module "example" {
  # You may need to remove the 'version' field, it is incompatible with some sources.
  source = "git::https://github.com/<USERNAME>/<REPO>.git//<MODULE-NAME>?ref=<BRANCH-NAME>"
}
```

## Adding/modifying README files

This repo uses Go to do a quick validation of each README. If you are working with the README files at all, it is strongly recommended that you install Go, so that the files can be validated locally.

### Validating all README files

To validate all README files throughout the entire repo, you can run the following:

```shell
go build ./cmd/readmevalidation && ./readmevalidation
```

The resulting binary is already part of the `.gitignore` file, but you can quickly remove it with:

```shell
rm ./readmevalidation
```

### README validation criteria

The following criteria exists for one of two reasons: (1) content accessibility, or (2) having content be designed in a way that's easy for the Registry site build step to use:

#### General README requirements

- There must be a frontmatter section.
- There must be exactly one h1 header, and it must be at the very top
- The README body (if it exists) must start with an h1 header. No other content (including GitHub-Flavored Markdown alerts) is allowed to be placed above it.
- When increasing the level of a header, the header's level must be incremented by one each time.
- Additional image/video assets can be placed in one of two places:
  - In the same user namespace directory where that user's main content lives
  - In the top-level `.icons` directory
- Any `.hcl` code snippets must be labeled as `.tf` snippets instead

  ```txt
  \`\`\`tf
  Content
  \`\`\`
  ```

#### Contributor profiles

- The README body is allowed to be empty, but if it isn't, it must follow all the rules above.
- The frontmatter supports the following fields:
  - `display_name` (required string) – The name to use when displaying your user profile in the Coder Registry site
  - `bio` (optional string) – A short description of who you are
  - `github` (required string) – Your GitHub handle
  - `avatar_url` (optional string) – A relative/absolute URL pointing to your avatar
  - `linkedin` (optional string) – A URL pointing to your LinkedIn page
  - `support_email` (optional string) – An email for users to reach you at if they need help with a published module/template
  - `employer_github` (optional string) – The name of another user namespace whom you'd like to have associated with your account. The namespace must also exist in the repo, or else the README validation will fail.
  - `status` (optional string union) – If defined, must be one of "community", "partner", or "official". "Community" is treated as the default value if not specified, and should be used for the majority of external contributions. "Official" should be used for Coder and Coder satellite companies. "Partner" is for companies who have a formal business agreement with Coder.

#### Modules and templates

- The frontmatter supports the following fields:
  - `description` (required string) A short description of what the module/template does.
  - `icon` (required string) – A URL pointing to the icon to use for the module/template when viewing it on the Registry website.
  - `display_name` (optional string) – A name to display instead of the name intuited from the module's/template's directory name
  - `verified` (optional boolean) – A boolean indicated that the Coder team has officially tested and vouched for the functionality/reliability of a given module or template. This field should only be changed by Coder employees.
  - `tags` (optional string array) – A list of tags to associate with the module/template. Users will be able to search for these tags from the Registry website.

## Releases

The release process is automated with these steps:

### 1. Create and merge a new PR

- Create a PR with your module changes
- Get your PR reviewed, approved, and merged into the `main` branch

### 2. Prepare Release (Maintainer Task)

After merging to `main`, a maintainer will:

- View all modules and their current versions:

  ```shell
  ./release.sh --list
  ```

- Determine the next version number based on changes:

  - **Patch version** (1.2.3 → 1.2.4): Bug fixes
  - **Minor version** (1.2.3 → 1.3.0): New features, adding inputs, deprecating inputs
  - **Major version** (1.2.3 → 2.0.0): Breaking changes (removing inputs, changing input types)

- Create and push an annotated tag:

  ```shell
  # Fetch latest changes
  git fetch origin
  
  # Create and push tag
  ./release.sh module-name 1.2.3 --push
  ```

  The tag format will be: `release/module-name/v1.2.3`

### 3. Publishing to Coder Registry

Our automated processes will handle publishing new data to [registry.coder.com](https://registry.coder.com).

> [!NOTE]
> Some data in registry.coder.com is fetched on demand from the [coder/modules](https://github.com/coder/modules) repo's `main` branch. This data should update almost immediately after a release, while other changes will take some time to propagate.
