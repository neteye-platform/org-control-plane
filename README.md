# GitHub Organization Control Plane

Infrastructure-as-code for the
[neteye-platform](https://github.com/neteye-platform)
GitHub organization (NetEye / Würth IT Italy).

Repositories, teams, and organization settings are declared
as YAML files and reconciled through Terraform with
Terragrunt orchestration. Changes are proposed via pull
request, planned automatically in CI, and applied on merge.

> **Production impact:** every change merged to `main`
> targets the live GitHub organization. Review plans
> carefully before approving.

## Repository Structure

```text
.
├── root.hcl                         # Remote state + provider
├── org-settings/                    # Org-level settings
│   └── terragrunt.hcl
├── teams/                           # Team management
│   ├── terragrunt.hcl
│   └── teams/
│       └── *.yaml                   # One file per team
├── repositories/                    # Repo management
│   ├── _defaults.yaml               # Org-wide defaults
│   └── <category>/
│       ├── _category_defaults.yaml  # Optional overrides
│       ├── terragrunt.hcl
│       └── repos/
│           └── *.yaml               # One file per repo
├── modules/                         # Terraform modules
│   ├── github-org-settings/
│   ├── github-repositories/
│   └── github-teams/
└── .github/workflows/
    ├── plan.yaml                    # Plan on PR
    └── apply.yaml                   # Apply on merge
```

Each top-level directory that contains a `terragrunt.hcl`
is a **Terragrunt unit**. The CI matrix is generated from
these directories automatically, so adding a new repository
category requires adding a `terragrunt.hcl` to its folder.

## Prerequisites

Terraform and Terragrunt are pinned separately:

- **Terraform** — version in `.terraform-version`
- **Terragrunt** — version in `mise.toml`

## Authentication

### CI

GitHub Actions authenticates via a
[GitHub App](https://docs.github.com/en/apps).
S3 remote state uses AWS credentials.
The required variables are configured as repository
secrets and variables

### Local

To run `terragrunt plan` locally you need the same
environment variables. Export them before running any
command:

```bash
# GitHub App credentials
export GITHUB_APP_ID="..."
export GITHUB_APP_INSTALLATION_ID="..."
export GITHUB_APP_PEM_FILE="..."

# AWS credentials for S3 remote state
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="..."

# Terraform variables
export TF_VAR_github_org="neteye-platform"
export TF_VAR_aws_region="$AWS_REGION"
export TF_VAR_billing_email="..."
```

## Configuration

### Adding a Repository

Create a YAML file in
`repositories/<category>/repos/`:

```yaml
# repositories/websites/repos/my-website.yaml
name: my-website
description: My website repository.
homepage_url: https://example.com
is_template: false
archived: false
```

Only fields that differ from the defaults are required.
Settings are merged in three tiers:

1. `repositories/_defaults.yaml` — org-wide defaults
2. `repositories/<category>/_category_defaults.yaml` —
   optional category overrides
3. `repositories/<category>/repos/<name>.yaml` —
   per-repo settings

To create a new repository **category**, add a directory
under `repositories/` with its own `terragrunt.hcl`
(copy from an existing category such as `websites/`).

### Branch Rulesets

Repository branch protection is managed with GitHub rulesets
through the `branch_ruleset` YAML block. The org-wide default
ruleset is declared in `repositories/_defaults.yaml` and applies
to every repository unless a category or repository overrides it.

```yaml
branch_ruleset:
  name: main-branch-protection
  target: branch
  enforcement: active
  conditions:
    ref_name:
      include:
        - main
      exclude: []
  rules:
    deletion: true
    non_fast_forward: true
    required_signatures: true
    pull_request:
      required_approving_review_count: 1
      dismiss_stale_reviews_on_push: true
      require_last_push_approval: true
      require_code_owner_review: true
      required_review_thread_resolution: true
    required_status_checks:
      strict_required_status_checks_policy: true
      required_check:
        - context: "common-pull-request-checks / pre-commit-checks / Pre-commit Checks"
    copilot_code_review:
      review_on_push: true
      review_draft_pull_requests: false
```

Scalar fields use normal precedence: repository overrides
category, category overrides org defaults. This applies to fields
such as `name`, `target`, `enforcement`, individual rule booleans,
pull request settings, required status check settings, and Copilot
review settings.

The following lists are additive across all tiers and are de-duplicated:

- `conditions.ref_name.include`
- `conditions.ref_name.exclude`
- `rules.required_status_checks.required_check`

Branch names in `conditions.ref_name.include` and
`conditions.ref_name.exclude` may be written as short names such as
`main`. The module expands them to `refs/heads/main`. Fully qualified
refs and GitHub ruleset tokens such as `~DEFAULT_BRANCH` are preserved.

`bypass_actors` is additive by default from org defaults plus
`extra_bypass_actors` at the category or repository tier:

```yaml
branch_ruleset:
  extra_bypass_actors:
    - actor_id: 5
      actor_type: RepositoryRole
      bypass_mode: pull_request
```

Set `bypass_actors` explicitly at the category or repository tier
when the inherited bypass list must be replaced instead of extended.
Use an empty list to remove all bypass actors for that scope:

```yaml
branch_ruleset:
  bypass_actors: []
```

`rules.merge_queue`, when configured, is not merged field-by-field.
The highest-priority tier that defines it wins entirely: repository,
then category, then org defaults.

### Adding a Team

Create a YAML file in `teams/teams/`:

```yaml
# teams/teams/my-team.yaml
name: my-team
description: My team description.
privacy: closed
notification_setting: notifications_enabled
```

### Organization Settings

Org-level settings are declared in
`org-settings/terragrunt.hcl`. Edit the `inputs` block
to change settings such as default repository permissions,
security scanning defaults, and member privileges.

## CI/CD Workflows

- **Common checks** — shared workflows imported from
  [repo-commons][rc] for PR validation, scheduled
  scans, and on-demand checks.
- **Terragrunt Plan** (`plan.yaml`) — runs on every PR
  to `main`. Plans each unit and posts results as PR
  comments.
- **Terraform Apply** (`apply.yaml`) — triggers on push
  to `main`. Applies each unit to the production
  environment.

[rc]: https://github.com/neteye-platform/repo-commons

## Local Development

```bash
# Install Terragrunt (via mise)
mise install

# Plan a single unit
terragrunt plan --terragrunt-working-dir teams

# Plan all units from the repo root
terragrunt run-all plan
```

## Security

See [SECURITY.md](SECURITY.md) for the vulnerability
disclosure policy.

## License

Dual-licensed under [Apache 2.0](LICENSE-APACHE) and
[MIT](LICENSE-MIT).
