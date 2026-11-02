# Copy this file to install.auto.tfvars and set your values. Terraform
# loads *.auto.tfvars on its own, and `coder templates push` leaves it out.

namespace          = "coder-workspaces"
workspace_image    = "registry.example.com/coder/workspace:v2.30.0"
coder_access_url   = "https://coder.example.com"
coder_egress_cidrs = ["203.0.113.10/32"]

# Fully isolated blocks DNS. If coder_access_url uses a host name, set the
# Coder server IP so the pools can resolve it.
# coder_host_ip = "203.0.113.10"

# Offer only the runtimes that your nodes have. See "Install the runtimes".
# runtimes = ["gvisor", "kata-qemu", "kata-clh"]

# A public repository that GitHub only pools clone while they wait.
# git_repo_url = "https://github.com/coder/coder"

# Amazon EKS with VPC CNI v1.21.1 or later only.
# enable_guardrail = true
