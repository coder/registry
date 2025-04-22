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

Follow the instructions to ensure that Bun is available globally.

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

## Releases

The release process is automated with these steps:

## 1. Create and merge a new PR

- Create a PR with your module changes
- Get your PR reviewed, approved, and merged into the `main` branch

## 2. Prepare Release (Maintainer Task)

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

## 3. Publishing to Coder Registry

Our automated processes will handle publishing new data to [registry.coder.com](https://registry.coder.com).

> [!NOTE]
> Some data in registry.coder.com is fetched on demand from the [coder/modules](https://github.com/coder/modules) repo's `main` branch. This data should update almost immediately after a release, while other changes will take some time to propagate.
