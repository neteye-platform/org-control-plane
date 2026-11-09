variable "teams" {
  description = "Teams to manage, keyed by team name."

  # The JSON Schemas in schemas/ are generated from this type: run
  # scripts/generate-schemas.py after a change. A comment line just before a
  # field becomes its description in the schema.
  type = map(object({
    # Team name. Must match the key.
    name = string
    # Team description.
    description = string
    # Team privacy: secret or closed.
    privacy = string
    # Team notifications: notifications_enabled or notifications_disabled.
    notification_setting = string
    # ID of the parent team.
    parent_team_id = optional(string)
    # Names of organization roles assigned to the team.
    org_roles = optional(list(string))
  }))

  validation {
    condition     = alltrue([for name, team in var.teams : team.name == name])
    error_message = "The \"name\" of a team must match its key."
  }
}
