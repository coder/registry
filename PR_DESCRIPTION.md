Closes #34

## Description

This PR adds conda package manager support to the JFrog modules, allowing users to configure conda to fetch packages from Artifactory repositories. The implementation follows the same patterns as existing package managers (npm, go, pypi, docker, maven) and provides consistent configuration across both JFrog OAuth and JFrog Token modules.

### Key Features Added:
- **Conda Configuration**: Added conda to the `package_managers` variable in both modules
- **Template Processing**: Created and integrated `condarc.tftpl` template for conda channel configuration
- **Smart Detection**: Scripts detect conda installation and create `.condarc` appropriately
- **Multiple Repositories**: Support for configuring multiple conda repositories
- **Documentation**: Comprehensive examples and usage instructions

## Type of Change

- [ ] New module
- [ ] Bug fix
- [x] Feature/enhancement
- [x] Documentation
- [ ] Other

## Module Information

**Modules Updated:**
- `registry/coder/modules/jfrog-oauth` - Enhanced with conda support
- `registry/coder/modules/jfrog-token` - Enhanced with conda support

**New version:** `v1.0.32` (suggested)  
**Breaking change:** [x] No

## Changes Made

### JFrog OAuth Module (`registry/coder/modules/jfrog-oauth/`)
- ✅ Added `conda` to `package_managers` variable with proper validation
- ✅ Added `condarc` template processing in locals section
- ✅ Added conda-related variables to script template
- ✅ Enhanced `run.sh` with conda configuration logic
- ✅ Updated README.md with conda examples and usage instructions
- ✅ Existing `condarc.tftpl` template was already present and functional

### JFrog Token Module (`registry/coder/modules/jfrog-token/`)
- ✅ Added `conda` to `package_managers` variable with proper validation
- ✅ Created `condarc.tftpl` template file
- ✅ Added `condarc` template processing in locals section
- ✅ Added conda-related variables to script template
- ✅ Enhanced `run.sh` with conda configuration logic
- ✅ Updated README.md with conda examples and usage instructions

## Usage Examples

### Basic Configuration
```terraform
module "jfrog" {
  # ... other configuration
  package_managers = {
    conda = ["conda-local", "conda-virtual"]
  }
}
```

### After Configuration
```bash
# Using JFrog CLI
jf conda install numpy

# Using conda directly  
conda install numpy
```

## Testing & Validation

- [x] Terraform validation passes (`terraform validate`)
- [x] Both modules initialize successfully (`terraform init`)
- [x] Configuration syntax is valid
- [x] Template files render correctly
- [x] Documentation examples are accurate
- [ ] Tests pass (`bun test`) - *Will run after PR submission*
- [ ] Code formatted (`bun run fmt`) - *Will run after PR submission*
- [x] Changes tested locally with terraform validate

## Related Issues

- Closes #34 - "Add conda package manager support to JFrog modules"
- Addresses the request from @matifali to add conda support similar to existing package managers

## Backward Compatibility

This change is fully backward compatible. Existing configurations will continue to work unchanged, and the conda support is opt-in via the `package_managers.conda` configuration.

## Files Modified

- `registry/coder/modules/jfrog-oauth/main.tf`
- `registry/coder/modules/jfrog-oauth/run.sh` 
- `registry/coder/modules/jfrog-oauth/README.md`
- `registry/coder/modules/jfrog-token/main.tf`
- `registry/coder/modules/jfrog-token/run.sh`
- `registry/coder/modules/jfrog-token/README.md`

## Files Added

- `registry/coder/modules/jfrog-token/condarc.tftpl`
