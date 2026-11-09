variable "billing_email" {
  description = "Billing email address of the organization"
  type        = string
  sensitive   = true
}

variable "settings" {
  description = "Organization-wide settings"

  # The JSON Schemas in schemas/ are generated from this type: run
  # scripts/generate-schemas.py after a change. A comment line just before a
  # field becomes its description in the schema.
  type = object({
    # Company name shown on the organization profile.
    company = string
    # URL shown on the organization profile.
    blog = string
    # Public email address of the organization.
    email = string
    # Twitter username of the organization.
    twitter_username = optional(string)
    # Location shown on the organization profile.
    location = string
    # Display name of the organization.
    name = string
    # Description of the organization.
    description = string
    # Enable projects at the organization level.
    has_organization_projects = bool
    # Enable projects at the repository level.
    has_repository_projects = bool
    # Base permission of members on all repositories: read, write, admin or none.
    default_repository_permission = string
    # Allow members to create repositories.
    members_can_create_repositories = bool
    # Allow members to create public repositories.
    members_can_create_public_repositories = bool
    # Allow members to create private repositories.
    members_can_create_private_repositories = bool
    # Allow members to create internal repositories.
    members_can_create_internal_repositories = bool
    # Allow members to create GitHub Pages sites.
    members_can_create_pages = bool
    # Allow members to create public GitHub Pages sites.
    members_can_create_public_pages = bool
    # Allow members to create private GitHub Pages sites.
    members_can_create_private_pages = bool
    # Allow members to fork private repositories.
    members_can_fork_private_repositories = bool
    # Require sign-off on commits made through the web interface.
    web_commit_signoff_required = bool
    # Enable GitHub Advanced Security on new repositories.
    advanced_security_enabled_for_new_repositories = bool
    # Enable Dependabot alerts on new repositories.
    dependabot_alerts_enabled_for_new_repositories = bool
    # Enable Dependabot security updates on new repositories.
    dependabot_security_updates_enabled_for_new_repositories = bool
    # Enable the dependency graph on new repositories.
    dependency_graph_enabled_for_new_repositories = bool
    # Enable secret scanning on new repositories.
    secret_scanning_enabled_for_new_repositories = bool
    # Enable secret scanning push protection on new repositories.
    secret_scanning_push_protection_enabled_for_new_repositories = bool
  })
}
