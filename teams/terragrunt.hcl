# Terragrunt configuration for GitHub organization team management
# Consumes the github-teams module to manage team creation, hierarchy, and membership

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}//modules/github-teams"
}

inputs = {
  # Path to directory containing team YAML files
  teams_yaml_dir = "${get_terragrunt_dir()}/teams"
}
