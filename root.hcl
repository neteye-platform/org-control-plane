# Root Terragrunt configuration for GitHub organization control plane
# Provides shared remote state, provider generation, and error handling for all child units

remote_state {
  backend = "s3"
  config = {
    # bucket       = "${local.tfstate_bucket}"
    bucket       = "ne-platform-github-tf-state"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.aws_region
    encrypt      = true
    use_lockfile = true
  }
}

# Generate provider.tf with GitHub provider using App authentication
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
terraform {
  required_version = ">= 1.5"

  required_providers {
    github = {
      source  = "integrations/github"
      version = ">= 6.0.0"
    }
  }
}

provider "github" {
  owner = "${local.github_org}"
  # Use environment variables for GitHub App authentication
  # GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID, GITHUB_APP_PEM_FILE
  app_auth {}

  retryable_errors = [429, 500, 502, 503, 504]
}
EOF
}

# Define locals for reuse across child units (with expose = true above)
locals {
  aws_region     = get_env("TF_VAR_aws_region")
  github_org     = get_env("TF_VAR_github_org")
  tfstate_bucket = "${local.aws_region}-${local.github_org}-tfstate"
}
