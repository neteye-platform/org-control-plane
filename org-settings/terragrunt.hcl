# Organization-wide settings

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}//modules/github-org-settings"
}

inputs = {
  settings      = yamldecode(file("${get_terragrunt_dir()}/settings.yaml"))
  billing_email = include.root.locals.ssm_parameters["org-settings/billing-email"]
}
