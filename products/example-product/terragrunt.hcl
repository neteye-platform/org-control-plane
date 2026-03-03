# Example product Terragrunt configuration
# Demonstrates the pattern all product groups should follow
# Loads org defaults, product overrides, and individual repo configurations

# Include root configuration to inherit remote state, provider generation, and error handling
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

# Dependency on teams to ensure they exist before repo team references
dependency "teams" {
  config_path = "../../teams"

  skip_outputs = true

  mock_outputs = {}

  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
}

# Reference the github-repos module
terraform {
  source = "${get_repo_root()}//modules/github-repos"
}

# Load configuration from org defaults and product overrides
locals {
  # Load organization-wide defaults
  org_defaults = yamldecode(file("${get_repo_root()}/_defaults.yaml"))

  # Load product-level defaults (optional overrides)
  product_defaults_path = "${get_terragrunt_dir()}/_product_defaults.yaml"
  product_defaults      = fileexists(local.product_defaults_path) ? yamldecode(file(local.product_defaults_path)) : {}

  # Path to individual repo YAML configurations
  repos_yaml_dir = "${get_terragrunt_dir()}/repos"

  # GitHub organization name from root locals
  github_org = include.root.locals.github_org
}

# Pass configuration to the module
inputs = {
  org_defaults     = local.org_defaults
  product_defaults = local.product_defaults
  repos_yaml_dir   = local.repos_yaml_dir
  github_org       = local.github_org
}
