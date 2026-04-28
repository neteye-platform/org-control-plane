output "repository_names" {
  description = "List of created repository names"
  value       = keys(github_repository.repos)
}

output "repository_urls" {
  description = "Map of repository name to clone URL"
  value = {
    for name, repo in github_repository.repos :
    name => repo.http_clone_url
  }
}
