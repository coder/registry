# Copy this file to install.auto.tfvars and set your values. Terraform
# loads *.auto.tfvars on its own, and `coder templates push` leaves it out.

# The namespace for workspaces. Terraform creates it.
namespace = "coder-workspaces"

# The image you built from build/Dockerfile, with a fixed tag or a digest.
workspace_image = "registry.example.com/coder/workspace:v2.30.0"

# The Coder access URL. Optional: each workspace passes its own access URL
# to the pool. Set it if Coder is not on port 443, or with coder_host_ip.
# coder_access_url = "https://coder.example.com"

# The IP ranges of the Coder server, as workspaces see it. Fully isolated
# workspaces can reach only these. Use the IP of the load balancer or
# ingress behind coder_access_url, for example the output of
# `dig +short coder.example.com`, with /32 for one address.
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
