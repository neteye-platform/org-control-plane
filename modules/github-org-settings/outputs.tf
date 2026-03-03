output "org_id" {
  description = "Organization ID"
  value       = github_organization_settings.org.id
}

output "webhook_ids" {
  description = "Map of webhook index to webhook ID"
  value = {
    for idx, webhook in github_organization_webhook.webhooks :
    idx => webhook.id
  }
}
