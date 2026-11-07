---
display_name: Xpra
description: Run any X11 desktop app as a full-size web app in Coder
icon: ../../../../.icons/desktop.svg
verified: false
tags: [desktop, gui, xpra, x11]
---

# Xpra

Run one X11 desktop app (an IDE, a reverse engineering tool, anything with a GUI) as a Coder app in the browser. Each instance starts its own [xpra](https://xpra.org) session with the app maximized, and the session resizes to match the browser window. You get the app, not a whole desktop.

```tf
module "ghidra" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/phorcys/xpra/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.main.id
  slug         = "ghidra"
  display_name = "Ghidra"
  command      = "/opt/ghidra/ghidraRun"
}
```

## How it works

- The install script installs xpra from the [xpra.org](https://xpra.org) repository and openbox from the distribution repository. It skips binaries that are already on `PATH`.
- The start script runs `xpra desktop` with openbox. Openbox maximizes the main windows without decorations and keeps dialogs floating.
- `--resize-display=yes` makes the X display follow the browser size, so the app always fills the window.
- xpra listens on `127.0.0.1` only. The Coder app proxy does the authentication.
- The session stops when the app exits. Restart the workspace to start it again.

## Examples

### Multiple apps

Use a unique `slug` and `port` for each instance:

```tf
module "gimp" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/phorcys/xpra/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.main.id
  slug         = "gimp"
  display_name = "GIMP"
  icon         = "/icon/gimp.svg"
  command      = "gimp"
  port         = 14500
}

module "android_studio" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/phorcys/xpra/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.main.id
  slug         = "android-studio"
  display_name = "Android Studio"
  command      = "/opt/android-studio/bin/studio.sh"
  port         = 14501
  open_in      = "tab"
}
```

### Environment and xpra tuning

```tf
module "ghidra" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/phorcys/xpra/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.main.id
  slug         = "ghidra"
  display_name = "Ghidra"
  command      = "/opt/ghidra/ghidraRun"
  env = {
    GDK_SCALE = "2"
  }
  extra_args = ["--min-quality=80"]
}
```

### Preinstalled xpra and openbox

The automatic install supports Debian and Ubuntu and needs passwordless `sudo`. On other images, install xpra (with the HTML5 client) and openbox in the image and turn off the install:

```tf
module "gimp" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/phorcys/xpra/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.main.id
  slug            = "gimp"
  command         = "gimp"
  install_xpra    = false
  install_openbox = false
}
```

## Limitations

- X11 only. Most Wayland-native toolkits can fall back to X11, for example with `GDK_BACKEND=x11` or `QT_QPA_PLATFORM=xcb` in `env`.
- The browser keeps some shortcuts (`Ctrl+W`, `Ctrl+T`, `Ctrl+N`) for itself.
- GTK apps that draw their own title bar still show it.
- Apps that need a GPU (3D, emulators) are slow without a GPU in the workspace.

## Troubleshooting

Each instance writes its scripts and logs to `$HOME/.coder-modules/phorcys/xpra-<slug>/`:

- `logs/install.log` and `logs/start.log` for the module scripts.
- `logs/xpra.log` for the xpra server and the app output.
