include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}//modules/github-teams"
}

locals {
  teams_dir = "${get_terragrunt_dir()}/teams"
}

inputs = {
  teams = {
    for f in fileset(local.teams_dir, "*.yaml") :
    trimsuffix(f, ".yaml") => yamldecode(file("${local.teams_dir}/${f}"))
  }
}
