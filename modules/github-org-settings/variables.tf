variable "settings" {
  description = "Organization-wide settings"
  type = object({
    default_repository_permission                                = optional(string)
    members_can_create_repositories                              = optional(bool)
    members_can_create_public_repositories                       = optional(bool)
    members_can_create_private_repositories                      = optional(bool)
    members_can_create_internal_repositories                     = optional(bool)
    web_commit_signoff_required                                  = optional(bool)
    has_organization_projects                                    = optional(bool)
    has_repository_projects                                      = optional(bool)
    advanced_security_enabled_for_new_repositories               = optional(bool)
    dependabot_alerts_enabled_for_new_repositories               = optional(bool)
    dependabot_security_updates_enabled_for_new_repositories     = optional(bool)
    dependency_graph_enabled_for_new_repositories                = optional(bool)
    secret_scanning_enabled_for_new_repositories                 = optional(bool)
    secret_scanning_push_protection_enabled_for_new_repositories = optional(bool)
    members_can_create_pages                                     = optional(bool)
    members_can_fork_private_repositories                        = optional(bool)
  })
  default = {}
}

variable "webhooks" {
  description = "Organization-level webhooks"
  type = list(object({
    url          = string
    content_type = optional(string)
    events       = list(string)
    active       = optional(bool)
    secret       = optional(string)
    insecure_ssl = optional(bool)
  }))
  default = []
}
