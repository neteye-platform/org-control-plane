# Terraform backend configuration for remote state
terraform {
  required_version = ">= 1.5"
  backend "s3" {}
}

resource "github_organization_settings" "org" {
  # Repository defaults
  default_repository_permission            = try(var.settings.default_repository_permission, "read")
  members_can_create_repositories          = try(var.settings.members_can_create_repositories, true)
  members_can_create_public_repositories   = try(var.settings.members_can_create_public_repositories, false)
  members_can_create_private_repositories  = try(var.settings.members_can_create_private_repositories, true)
  members_can_create_internal_repositories = try(var.settings.members_can_create_internal_repositories, true)

  # Other org settings
  web_commit_signoff_required = try(var.settings.web_commit_signoff_required, false)
  has_organization_projects   = try(var.settings.has_organization_projects, false)
  has_repository_projects     = try(var.settings.has_repository_projects, true)

  # Advanced security
  advanced_security_enabled_for_new_repositories           = try(var.settings.advanced_security_enabled_for_new_repositories, false)
  dependabot_alerts_enabled_for_new_repositories           = try(var.settings.dependabot_alerts_enabled_for_new_repositories, true)
  dependabot_security_updates_enabled_for_new_repositories = try(var.settings.dependabot_security_updates_enabled_for_new_repositories, true)
  dependency_graph_enabled_for_new_repositories            = try(var.settings.dependency_graph_enabled_for_new_repositories, true)
}

resource "github_organization_webhook" "webhooks" {
  for_each = {
    for idx, webhook in var.webhooks :
    idx => webhook
  }

  events = each.value.events

  configuration {
    url          = each.value.url
    content_type = try(each.value.content_type, "form")
    secret       = try(each.value.secret, null)
    insecure_ssl = try(each.value.insecure_ssl, false)
  }

  active = try(each.value.active, true)
}
