terraform {
  required_version = ">= 1.5"
  backend "s3" {}
}

resource "github_organization_settings" "org" {
  billing_email                                                = sensitive(var.settings.billing_email)
  company                                                      = var.settings.company
  blog                                                         = var.settings.blog
  email                                                        = var.settings.email
  twitter_username                                             = try(var.settings.twitter_username, null)
  location                                                     = var.settings.location
  name                                                         = var.settings.name
  description                                                  = var.settings.description
  has_organization_projects                                    = var.settings.has_organization_projects
  has_repository_projects                                      = var.settings.has_repository_projects
  default_repository_permission                                = var.settings.default_repository_permission
  members_can_create_repositories                              = var.settings.members_can_create_repositories
  members_can_create_public_repositories                       = var.settings.members_can_create_public_repositories
  members_can_create_private_repositories                      = var.settings.members_can_create_private_repositories
  members_can_create_internal_repositories                     = var.settings.members_can_create_internal_repositories
  members_can_create_pages                                     = var.settings.members_can_create_pages
  members_can_create_public_pages                              = var.settings.members_can_create_public_pages
  members_can_create_private_pages                             = var.settings.members_can_create_private_pages
  members_can_fork_private_repositories                        = var.settings.members_can_fork_private_repositories
  web_commit_signoff_required                                  = var.settings.web_commit_signoff_required
  advanced_security_enabled_for_new_repositories               = var.settings.advanced_security_enabled_for_new_repositories
  dependabot_alerts_enabled_for_new_repositories               = var.settings.dependabot_alerts_enabled_for_new_repositories
  dependabot_security_updates_enabled_for_new_repositories     = var.settings.dependabot_security_updates_enabled_for_new_repositories
  dependency_graph_enabled_for_new_repositories                = var.settings.dependency_graph_enabled_for_new_repositories
  secret_scanning_enabled_for_new_repositories                 = var.settings.secret_scanning_enabled_for_new_repositories
  secret_scanning_push_protection_enabled_for_new_repositories = var.settings.secret_scanning_push_protection_enabled_for_new_repositories

  # Prevent destruction of org settings to avoid accidental deletion of critical configuration
  lifecycle {
    prevent_destroy = true
  }

}
