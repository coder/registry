# VS Code Desktop Enhanced: Pre-install Extensions and Apply Settings

## Summary

This PR introduces a new **VS Code Desktop Enhanced** module that extends the existing VS Code Desktop functionality by adding support for automatically pre-installing VS Code extensions and applying custom settings when users connect to Coder workspaces.

## Features

### 🚀 **Automatic Extension Installation**
- Pre-install specified VS Code extensions on workspace startup
- Supports any VS Code extension available in the marketplace
- Extensions are installed on the remote host (workspace)
- Graceful handling of installation failures

### ⚙️ **Custom Settings Configuration**
- Apply custom VS Code settings in JSON format
- Settings persist across workspace restarts
- Overwrites existing settings (future enhancement could support merging)

### 📁 **Workspace Configuration**
- Creates `.vscode/extensions.json` with recommended extensions
- Team-friendly setup for consistent development environments

### 🔄 **Backward Compatibility**
- Fully compatible with existing VS Code Desktop module
- All existing parameters (`folder`, `open_recent`, `order`, `group`) are supported

## Usage Examples

### Basic Extension Installation
```hcl
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop-enhanced/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  
  extensions = [
    "ms-python.python",
    "ms-vscode.vscode-typescript-next",
    "esbenp.prettier-vscode"
  ]
}
```

### Full Configuration with Settings
```hcl
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop-enhanced/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
  
  extensions = [
    "ms-python.python",
    "ms-python.pylint",
    "ms-python.black-formatter"
  ]
  
  settings = jsonencode({
    "python.defaultInterpreterPath" = "/usr/bin/python3"
    "editor.fontSize" = 14
    "editor.formatOnSave" = true
    "workbench.colorTheme" = "Dark+ (default dark)"
  })
}
```

### Team Development Setup
```hcl
locals {
  team_extensions = [
    "ms-vscode.vscode-typescript-next",
    "esbenp.prettier-vscode",
    "ms-vscode.vscode-eslint"
  ]
  
  team_settings = {
    "editor.formatOnSave" = true
    "editor.tabSize" = 2
    "prettier.singleQuote" = true
  }
}

module "vscode" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/vscode-desktop-enhanced/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.example.id
  extensions = local.team_extensions
  settings   = jsonencode(local.team_settings)
}
```

## Implementation Details

### Architecture
- Uses `coder_script` resource to run setup script on workspace start
- Script only runs when extensions or settings are specified
- Embedded shell script handles all setup logic
- Creates necessary VS Code server directories automatically

### Extension Installation Process
1. Checks for VS Code CLI availability
2. Downloads and installs VS Code CLI if not present
3. Installs each extension with `--force` flag
4. Creates workspace recommendations file

### Settings Application
1. Creates VS Code settings directory structure
2. Writes settings directly to `settings.json`
3. Future enhancement: support merging with existing settings using `jq`

## Testing

Comprehensive test suite with **10 passing tests** covering:
- ✅ Default behavior without extensions
- ✅ Folder and open_recent parameters
- ✅ Extension installation
- ✅ Settings configuration
- ✅ Combined extensions and settings
- ✅ Empty extensions list handling
- ✅ Complex settings objects
- ✅ UI ordering and grouping

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `agent_id` | The ID of a Coder agent | `string` | n/a | yes |
| `folder` | The folder to open in VS Code | `string` | `""` | no |
| `open_recent` | Open the most recent workspace or folder | `bool` | `false` | no |
| `order` | The order determines the position of app in the UI presentation | `number` | `null` | no |
| `group` | The name of a group that this app belongs to | `string` | `null` | no |
| `extensions` | List of VS Code extension IDs to pre-install | `list(string)` | `[]` | no |
| `settings` | VS Code settings in JSON format to be applied | `string` | `"{}"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vscode_url` | VS Code Desktop URL |
| `extensions_installed` | List of VS Code extensions that will be installed |
| `settings_applied` | Status of VS Code settings configuration |

## Future Enhancements

1. **Settings Merging**: Use `jq` to merge new settings with existing ones instead of overwriting
2. **Extension Version Pinning**: Support specifying extension versions
3. **Conditional Extensions**: Support platform-specific extensions
4. **Extension Installation Status**: Better feedback on extension installation success/failure
5. **Keybindings Support**: Add support for custom keybindings configuration

## Breaking Changes

None. This is a new module that doesn't affect existing functionality.

## Related Issues

Resolves #207 - Pre-install VS Code extensions in desktop VS Code module

## Files Changed

- `registry/coder/modules/vscode-desktop-enhanced/main.tf` - Main Terraform module
- `registry/coder/modules/vscode-desktop-enhanced/README.md` - Documentation and examples
- `registry/coder/modules/vscode-desktop-enhanced/main.test.ts` - Comprehensive test suite

## Verification

The module has been thoroughly tested with:
- Unit tests (10/10 passing)
- Multiple usage scenarios
- Error handling for edge cases
- Terraform validation

Ready for review and merge! 🎉
