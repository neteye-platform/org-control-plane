# Organization-wide settings configuration

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}//modules/github-org-settings"
}

locals {
  settings = yamldecode(file("${get_terragrunt_dir()}/settings.yaml"))
}

inputs = {
  settings = merge(local.settings, {
    billing_email = get_env("TF_VAR_billing_email")
  })
}
