# Included by every unit. Needs only an AWS session, see the README.

locals {
  github_org     = "neteye-platform"
  aws_region     = "eu-south-1"
  tfstate_bucket = "${local.aws_region}-${local.github_org}-tfstate"
  ssm_prefix     = "/org-control-plane"

  # One AWS call for the whole run. Keys are the names without the prefix.
  ssm_parameters = {
    for p in jsondecode(run_cmd(
      "--terragrunt-quiet", "--terragrunt-global-cache",
      "aws", "ssm", "get-parameters-by-path",
      "--region", local.aws_region,
      "--path", local.ssm_prefix,
      "--recursive",
      "--with-decryption",
      "--query", "Parameters[].[Name,Value]",
      "--output", "json",
    )) : trimprefix(p[0], "${local.ssm_prefix}/") => p[1]
  }
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket = local.tfstate_bucket
    # Same key as before the stacks, for example repositories/ai/terraform.tfstate.
    key          = "${replace(path_relative_to_include(), ".terragrunt-stack/", "")}/terraform.tfstate"
    region       = local.aws_region
    encrypt      = true
    use_lockfile = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "github" {
      owner = "${local.github_org}"

      app_auth {}

      retryable_errors = [429, 500, 502, 503, 504]
    }
  EOF
}

# One provider lock file for every unit.
generate "lock_file" {
  path      = ".terraform.lock.hcl"
  if_exists = "overwrite"
  contents  = file("${get_repo_root()}/.terraform.lock.hcl")
}

terraform {
  copy_terraform_lock_file = false

  extra_arguments "lock_file_readonly" {
    commands  = ["init"]
    arguments = ["-lockfile=readonly"]
  }

  extra_arguments "retry_lock" {
    commands  = get_terraform_commands_that_need_locking()
    arguments = ["-lock-timeout=20m"]
  }

  # Environment variables only, never written to disk.
  extra_arguments "github_app_credentials" {
    commands = get_terraform_commands_that_need_vars()
    env_vars = {
      GITHUB_APP_ID              = local.ssm_parameters["github-app/app-id"]
      GITHUB_APP_INSTALLATION_ID = local.ssm_parameters["github-app/installation-id"]
      GITHUB_APP_PEM_FILE        = local.ssm_parameters["github-app/private-key"]
    }
  }
}
