# Contributing

## Getting started

This repo uses two main runtimes to verify the correctness of a module/template before it is published:

- [Bun](https://bun.sh/) – Used to run tests for each module/template to validate overall functionality and correctness of Terraform output
- [Go](https://go.dev/) – Used to validate all README files in the directory. The README content is used to populate [the Registry website](https://registry.coder.com).

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

## Namespaces

All Coder resources are scoped to namespaces placed at the top level of the `/registry` directory. Any modules or templates must be placed inside a namespace to be accepted as a contribution. For example, all modules created by CoderEmployeeBob would be placed under `/registry/coderemployeebob/modules`, with a subdirectory for each individual module the user has published.

If a namespace is already taken, you will need to create a different, unique namespace, but will still be able to choose any display name. (The display name is shown in the Registry website. More info below.)

### Namespace (contributor profile) README files

More information about contributor profile README files can be found below.

### Images

Any images needed for either the main namespace directory or a module/template can be placed in a relative `/images` directory at the top of the namespace directory. (e.g., CoderEmployeeBob can have a `/registry/coderemployeebob/images` directory, that can be referenced by the main README file, as well as a README file in `/registry/coderemployeebob/modules/custom_module/README.md`.) This is to minimize the risk of file name conflicts between different users as they add images to help illustrate parts of their README files.

## Coder modules

### Adding a new module

> [!WARNING]
> These instructions cannot be followed just yet; the script referenced will be made available shortly. Contributors looking to add modules early will need to create all directories manually.

Once Bun (and possibly Go) have been installed, clone the Coder Registry repository. From there, you can run this script to make it easier to start contributing a new module or template:

```shell
./new.sh USER_NAMESPACE/NAME_OF_NEW_MODULE
```

You can also create a module file manually by creating the necessary files and directories.

### The composition of a Coder module

Each Coder Module must contain the following files:

- A `main.tf` file that defines the main Terraform-based functionality
- A `main.test.ts` file that is used to validate that the module works as expected
- A `README.md` file containing required information (listed below)

You are free to include any additional files in the module, as needed by the module. For example, the [Windows RDP module](https://github.com/coder/registry/tree/main/registry/coder/modules/windows-rdp) contains additional files for injecting specific functionality into a Coder Workspace.

> [!NOTE]
> Some legacy modules do not have test files defined just yet. This will be addressed soon.

### The `main.tf` file

This file defines all core Terraform functionality, to be mixed into your Coder workspaces. More information about [Coder's use of Terraform can be found here](https://coder.com/docs/admin/templates/extending-templates/modules), and [general information about the Terraform language can be found in the official documentation](https://developer.hashicorp.com/terraform/docs).

### The structure of a module README

Validation criteria for module README files is listed below.

### Testing a Module

> [!IMPORTANT]
> It is the responsibility of the module author to implement tests for every new module they wish to contribute. It is expected the author has tested the module locally before opening a PR. Feel free to reference existing test files to get an idea for how to set them up.

All general-purpose test helpers for validating Terraform can be found in the top-level `/testing` directory. The helpers run `terraform apply` on modules that use variables, testing the script output against containers.

When writing a test file, you can import the test utilities via the `~test` import alias:

```ts
// This works regardless of how deeply-nested your test file is in the file
// structure
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";
```

> [!NOTE]
> The testing suite must be able to run docker containers with the `--network=host` flag. This typically requires running the tests on Linux as this flag does not apply to Docker Desktop for MacOS or Windows. MacOS users can work around this by using something like [colima](https://github.com/abiosoft/colima) or [Orbstack](https://orbstack.dev/) instead of Docker Desktop.

#### Running tests

You can run all tests by running this command from the root of the Registry directory:

```shell
bun test
```

Note that running _all_ tests can take some time, so you likely don't want to be running this command as part of your core development loop.

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

## Updating README files

This repo uses Go to validate each README file. If you are working with the README files at all (i.e., creating them, modifying them), it is strongly recommended that you install Go (installation instructions mentioned above), so that the files can be validated locally.

### Validating all README files

To validate all README files throughout the entire repo, you can run the following:

```shell
go build ./cmd/readmevalidation && ./readmevalidation
```

The resulting binary is already part of the `.gitignore` file, but you can remove it with:

```shell
rm ./readmevalidation
```

### README validation criteria

The following criteria exists for two reasons:

1. Content accessibility
2. Having content be designed in a way that's easy for the Registry site build step to use

#### General README requirements

- There must be a frontmatter section.
- There must be exactly one h1 header, and it must be at the very top, directly below the frontmatter.
- The README body (if it exists) must start with an h1 header. No other content (including GitHub-Flavored Markdown alerts) is allowed to be placed above it.
- When increasing the level of a header, the header's level must be incremented by one each time.
- Any `.hcl` code snippets must be labeled as `.tf` snippets instead

  ```txt
  \`\`\`tf
  Content
  \`\`\`
  ```

#### Namespace (contributor profile) criteria

In addition to the general criteria, all README files must have the following:

- Frontmatter metadata with support for the following fields:

  - `display_name` (required string) – The name to use when displaying your user profile in the Coder Registry site.
  - `bio` (optional string) – A short description of who you are.
  - `github` (optional string) – Your GitHub handle.
  - `avatar_url` (optional string) – A relative/absolute URL pointing to your avatar for the Registry site. It is strongly recommended that you commit avatar images to this repo and reference them via a relative URL.
  - `linkedin` (optional string) – A URL pointing to your LinkedIn page.
  - `support_email` (optional string) – An email for users to reach you at if they need help with a published module/template.
  - `status` (string union) – If defined, this must be one of `"community"`, `"partner"`, or `"official"`. `"community"` should be used for the majority of external contributions. `"partner"` is for companies who have a formal business partnership with Coder. `"official"` should be used only by Coder employees.

- The README body (the content that goes directly below the frontmatter) is allowed to be empty, but if it isn't, it must follow all the rules above.

You are free to customize the body of a contributor profile however you like, adding any number of images or information. Its content will never be rendered in the Registry website.

Additional information can be placed in the README file below the content listed above, using any number of headers.

Additional image/video assets can be placed in the same user namespace directory where that user's main content lives.

#### Module criteria

In addition to the general criteria, all README files must have the following:

- Frontmatter that describes metadata for the module:
  - `display_name` (required string) – This is the name displayed on the Coder Registry website
  - `description` (required string) – A short description of the module, which is displayed on the Registry website
  - `icon` (required string) – A relative/absolute URL pointing to the icon to display for the module in the Coder Registry website.
  - `verified` (optional boolean) – Indicates whether the module has been officially verified by Coder. Please do not set this without approval from a Coder employee.
  - `tags` (required string array) – A list of metadata tags to describe the module. Used in the Registry site for search and navigation functionality.
  - `maintainer_github` (deprecated string) – The name of the creator of the module. This field exists for backwards compatibility with previous versions of the Registry, but going forward, the value will be inferred from the namespace directory.
  - `partner_github` (deprecated string) - The name of any additional creators for a module. This field exists for backwards compatibility with previous versions of the Registry, but should not ever be used going forward.
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

Additional information can be placed in the README file below the content listed above, using any number of headers.

Additional image/video assets can be placed in one of two places:

1. In the same user namespace directory where that user's main content lives
2. If the image is an icon, it can be placed in the top-level `.icons` directory (this is done because a lot of modules will be based off the same products)

## Releases

The release process involves the following steps:

### 1. Create and merge a new PR

- Create a PR with your module changes
- Get your PR reviewed, approved, and merged into the `main` branch

### 2. Prepare Release (Maintainer Task)

After merging to `main`, a maintainer will:

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
