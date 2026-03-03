# Organization-wide settings configuration
# Manages GitHub organization settings and webhooks (NOT member management)
# Member management is handled by SCIM/SAML layer, not Terraform

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}//modules/github-org-settings"
}

inputs = {
  github_org = include.root.locals.github_org

  settings = {
    # Security defaults: conservative permissions for new repositories
    default_repository_permission            = "read"
    members_can_create_repositories          = false
    members_can_create_public_repositories   = false
    members_can_create_private_repositories  = true
    members_can_create_internal_repositories = true
    web_commit_signoff_required              = false

    # Dependabot and security features enabled by default
    dependabot_alerts_enabled_for_new_repositories           = true
    dependabot_security_updates_enabled_for_new_repositories = true
    dependency_graph_enabled_for_new_repositories            = true
    advanced_security_enabled_for_new_repositories           = false

    # GitHub Projects and discussions
    has_organization_projects = false
    has_repository_projects   = true

    # Member visibility and invite settings
    members_can_create_pages = true
  }

  # No webhooks configured by default; can be added per deployment via tfvars
  webhooks = []
}
