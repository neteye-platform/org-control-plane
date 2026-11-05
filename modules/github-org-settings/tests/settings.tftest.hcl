# Organization settings.

mock_provider "github" {}

variables {
  billing_email = "billing@example.com"
  settings = {
    company                                                      = "Example"
    blog                                                         = "https://example.com"
    email                                                        = ""
    location                                                     = "Italy"
    name                                                         = "Example org"
    description                                                  = "An example"
    has_organization_projects                                    = false
    has_repository_projects                                      = true
    default_repository_permission                                = "read"
    members_can_create_repositories                              = true
    members_can_create_public_repositories                       = true
    members_can_create_private_repositories                      = false
    members_can_create_internal_repositories                     = false
    members_can_create_pages                                     = false
    members_can_create_public_pages                              = false
    members_can_create_private_pages                             = false
    members_can_fork_private_repositories                        = false
    web_commit_signoff_required                                  = true
    advanced_security_enabled_for_new_repositories               = true
    dependabot_alerts_enabled_for_new_repositories               = true
    dependabot_security_updates_enabled_for_new_repositories     = false
    dependency_graph_enabled_for_new_repositories                = true
    secret_scanning_enabled_for_new_repositories                 = true
    secret_scanning_push_protection_enabled_for_new_repositories = false
  }
}

run "settings" {
  command = plan

  assert {
    condition = (
      github_organization_settings.org.billing_email == "billing@example.com" &&
      github_organization_settings.org.twitter_username == null
    )
    error_message = "billing_email must come from its own variable, twitter_username must be optional"
  }

  assert {
    condition = alltrue([
      for field, value in var.settings : github_organization_settings.org[field] == value if value != null
    ])
    error_message = "every setting must be passed to the resource with the same name"
  }
}

run "twitter_username" {
  command = plan

  variables {
    settings = merge(var.settings, { twitter_username = "example" })
  }

  assert {
    condition     = github_organization_settings.org.twitter_username == "example"
    error_message = "twitter_username must be passed to the resource"
  }
}
