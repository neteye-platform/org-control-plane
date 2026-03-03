# Loads org defaults, category overrides, and individual repo configurations

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

# Dependency on teams to ensure they exist before repo team references
dependency "teams" {
  config_path = "../../teams"

  mock_outputs = {}

  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
}

# Reference the github-repos module
terraform {
  source = "${get_repo_root()}//modules/github-repositories"
}

# Load configuration from org defaults and category overrides
locals {
  # Load organization-wide repositories defaults
  org_defaults = yamldecode(file("${get_repo_root()}/repositories/_defaults.yaml"))

  # Load category-level defaults if the file exists
  category_defaults_path = "${get_terragrunt_dir()}/_category_defaults.yaml"
  category_defaults      = fileexists(local.category_defaults_path) ? yamldecode(file(local.category_defaults_path)) : tomap({})

  # Path to individual repo YAML configurations
  repos_yaml_dir = "${get_terragrunt_dir()}/repos"
}

# Pass configuration to the module
inputs = {
  org_defaults      = local.org_defaults
  category_defaults = local.category_defaults
  repos_yaml_dir    = local.repos_yaml_dir
}
