---
display_name: Kubernetes Cluster Version
icon: ../../../../.icons/kubernetes.svg
description: A parameter for selecting the Kubernetes cluster version for the workspace.
verified: false
tags: [helper, parameter, kubernetes]
---

# Kubernetes Cluster Version

Adds a `coder_parameter` with stable Kubernetes release channel options to any template.

```tf
module "k8s-cluster-version" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/matifali/k8s-cluster-version/coder"
  version = "1.0.0"
  default = "1.31"
}
```
