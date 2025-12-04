# Run 'terraform test' from this template directory (where main.tf lives)

# --- Mock cloud providers so no external calls happen ---
mock_provider "aws" {}
mock_provider "kubernetes" {}

# Provide fake values for data sources your template reads
override_data {
  target = data.aws_eks_cluster.eks
  values = {
    name     = "unit-test-eks"
    endpoint = "https://example.eks.local"
    certificate_authority = [{
      data = base64encode("dummy-ca")
    }]
  }
}

override_data {
  target = data.aws_eks_cluster_auth.eks
  values = {
    token = "dummy-token"
  }
}

# ---------------------------
# 1) Validate configuration
# ---------------------------
run "validate" {
  command = validate
}

# ---------------------------
# 2) Plan with representative inputs
# ---------------------------
run "plan_with_defaults" {
  command = plan

  variables {
    host_cluster_name = "unit-test-eks"

    # IaC/tooling toggles
    iac_tool     = "terraform"
    enable_aws   = true
    enable_azure = false
    enable_gcp   = false

    # Dev creds (empty OK for unit test)
    aws_access_key_id     = ""
    aws_secret_access_key = ""
    azure_client_id       = ""
    azure_tenant_id       = ""
    azure_client_secret   = ""
    gcp_service_account   = ""
  }

  # Simple sanity assertions (adjust resource addresses to your template)
  assert {
    condition     = can(resource.kubernetes_namespace.workspace)
    error_message = "kubernetes_namespace.workspace was not created in plan."
  }

  assert {
    condition     = can(resource.coder_agent.main)
    error_message = "coder_agent.main was not planned."
  }
}

# ---------------------------
# 3) Plan with CDK selected
# ---------------------------
run "plan_with_cdk" {
  command = plan
  variables {
    host_cluster_name = "unit-test-eks"
    iac_tool          = "cdk"
    enable_aws        = true
    enable_azure      = false
    enable_gcp        = false
  }

  # Ensure the env reflects choice (string map lookup)
  assert {
    condition     = contains(keys(resource.coder_agent.main.env), "IAC_TOOL")
    error_message = "IAC_TOOL env not present on coder_agent.main."
  }
}
