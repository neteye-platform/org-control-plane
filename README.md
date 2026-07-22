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
│   ├── settings.yaml                # Settings values
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
    ├── apply.yaml                   # Apply on merge
    ├── plan-core.yaml               # Reusable plan job
    ├── apply-core.yaml              # Reusable apply job
    └── generate-matrix.yaml         # Discovers Terragrunt units
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
secrets and variables.

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
name: my-website
description: My website repository.
homepage_url: https://example.com
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

See the [`github_repository`][tf-repo] resource docs
for the full list of available fields.

[tf-repo]: https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository

### Team Access

Repository team permissions are managed through the `team_access` YAML list.
Each entry specifies a team slug and one of the GitHub permission levels:
`pull` (read), `triage`, `push` (write), `maintain`, or `admin`.

The org-wide default in `repositories/_defaults.yaml` applies to every
repository:

```yaml
team_access:
  - team: rd-developers
    permission: push
```

`team_access` is inherited by default from the highest tier that sets it.
A category-level `team_access` replaces the org default; a repo-level
`team_access` replaces both category and org values.

Use `extra_team_access` to keep the inherited `team_access` list and add
or override entries (matched by team slug) at the category or repo tier:

```yaml
# Keep inherited teams and grant rd-developers maintain access,
# plus add a new team for this repo only.
extra_team_access:
  - team: rd-developers
    permission: maintain
  - team: my-extra-team
    permission: push
```

Set `team_access` explicitly when the inherited list must be replaced
instead of extended. Use an empty list to remove all team access for
that scope:

```yaml
team_access: []
```

### User Access

Repository per-user permissions are managed through the `user_access` YAML
list, which mirrors `team_access` but takes a GitHub `username` instead of
a team slug. Each entry uses the same permission levels: `pull` (read),
`triage`, `push` (write), `maintain`, or `admin`.

`user_access` follows the same inheritance rules as `team_access`: the
highest tier that defines it wins entirely; lower tiers are not merged
in. Collaborators are usually scoped to a single repository, so this
list is typically declared per-repo:

```yaml
user_access:
  - username: external-contributor
    permission: push
```

Use `extra_user_access` to keep the inherited `user_access` list and add
or override entries (matched by username) at the category or repo tier:

```yaml
extra_user_access:
  - username: external-contributor
    permission: maintain
```

Use an empty list to remove all user access for that scope:

```yaml
user_access: []
```

Adding a user creates a pending GitHub invitation that the user must
accept before gaining access; pending invitations do not expire.
Destroying the resource revokes the invitation if unaccepted, otherwise
removes the collaborator. See the
[`github_repository_collaborator`][tf-collab] resource docs for details.

[tf-collab]: https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_collaborator

### Labels

Repository issue and pull-request labels are managed through the `labels`
YAML list. Each entry has a `name`, a 6-digit hex `color` (without the
leading `#`), and a `description`:

```yaml
labels:
  - name: bug
    color: D73A4A
    description: "Something isn't working"
  - name: feature
    color: 3DB6D1
    description: "New feature or request"
```

`labels` is inherited from the highest tier that sets it. A category-level
`labels` replaces the org default; a repo-level `labels` replaces both.
Define org-wide defaults in `repositories/_defaults.yaml` to apply them to
every repository.

Use `extra_labels` at the category or repo tier to **add** labels alongside
the inherited `labels` list. Unlike `extra_team_access`, `extra_labels`
**cannot override** entries already defined in `labels` — names already
present in the base set are kept as-is. Within `extra_labels`, repo entries
override category entries by name (most-specific wins).

```yaml
extra_labels:
  - name: my-custom-label
    color: FBCA04
    description: "Using this label will be fun!"
```

To change the color or description of an inherited label, override it at
the appropriate tier by adding it to that tier's `labels:` list. Use an
empty list to remove all labels for that scope:

```yaml
labels: []
```

Labels are managed with the authoritative
[`github_issue_labels`][tf-labels] resource: **any label that exists on
the repository but is not present in the merged `labels`/`extra_labels`
result is deleted**, including GitHub's auto-generated defaults (e.g.
`bug`, `enhancement`, `good first issue`). Declare every label you want
to keep — the org-wide `labels` list in `repositories/_defaults.yaml`
already covers the common set.

Renaming a label (changing its `name`) deletes the old label and creates
a new one, detaching it from any issues or pull requests it was
previously attached to. Changing only the `color` or `description`
updates the existing label in place.

[tf-labels]: https://registry.terraform.io/providers/integrations/github/latest/docs/resources/issue_labels

### Branch Rulesets

Repository branch protection is managed with
[GitHub rulesets][tf-ruleset] through the `branch_rulesets`
YAML map. Each key is the ruleset name. The org-wide
defaults are declared in `repositories/_defaults.yaml`
and apply to every repository. Categories and individual
repositories can override existing rulesets or define
additional ones.

[tf-ruleset]: https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_ruleset

```yaml
branch_rulesets:
  main-branch-protection:
    target: branch
    enforcement: active
    bypass_actors:
      - actor_id: 0
        actor_type: OrganizationAdmin
        bypass_mode: pull_request
    conditions:
      ref_name:
        include:
          - main
        exclude: []
    rules:
      creation: true
      deletion: true
      update: true
      non_fast_forward: true
      required_linear_history: true
      required_signatures: true
      pull_request:
        allowed_merge_methods:
          - "squash"
        required_approving_review_count: 1
        dismiss_stale_reviews_on_push: true
        require_last_push_approval: true
        require_code_owner_review: true
        required_review_thread_resolution: true
      required_status_checks:
        strict_required_status_checks_policy: true
        required_check:
          - context: >-
              common-pull-request-checks / pre-commit-checks / Pre-commit Checks
            integration_id: 15368 # GH Actions
      required_code_scanning:
        required_code_scanning_tool:
          - tool: CodeQL
            alerts_threshold: errors
            security_alerts_threshold: critical
      merge_queue:
        grouping_strategy: ALLGREEN
        merge_method: SQUASH
        check_response_timeout_minutes: 60
        min_entries_to_merge: 1
        max_entries_to_merge: 5
        min_entries_to_merge_wait_minutes: 5
        max_entries_to_build: 5
      copilot_code_review:
        review_on_push: true
        review_draft_pull_requests: false
```

#### Merge behaviour

Scalar fields use normal precedence: repository overrides
category, category overrides org defaults. This applies to
fields such as `target`, `enforcement`, individual rule
booleans, pull request settings, required status check
settings, and Copilot review settings.

Rulesets are matched by name across tiers. A category or
repository that defines a ruleset with the same key as an
org default overrides its fields. A new key adds a
ruleset that only applies to that category or repository.

The following lists are **additive** across all tiers and
are de-duplicated:

- `conditions.ref_name.include`
- `conditions.ref_name.exclude`
- `rules.required_status_checks.required_check`

`rules.required_code_scanning.required_code_scanning_tool`
is merged by tool name with repo > category > org
precedence. A lower tier can override thresholds for an
inherited tool or add new tools.

Branch names in `conditions.ref_name.include` and
`conditions.ref_name.exclude` may be written as short
names such as `main`. The module expands them to
`refs/heads/main`. Fully qualified refs and GitHub ruleset
tokens such as `~DEFAULT_BRANCH` are preserved.

`rules.merge_queue`, when configured, is not merged
field-by-field. The highest-priority tier that defines it
wins entirely: repository, then category, then org
defaults.

#### Bypass actors

`bypass_actors` is taken from the **first** tier that
defines it, exclusively: repository overrides category,
category overrides org defaults. Use an empty list to
remove all bypass actors for that scope:

```yaml
branch_rulesets:
  main-branch-protection:
    bypass_actors: []
```

`extra_bypass_actors` from **all** tiers (org, category,
repo) are **always** appended to the final list, regardless
of which tier provided the base `bypass_actors`:

```yaml
branch_rulesets:
  main-branch-protection:
    extra_bypass_actors:
      - actor_id: 5
        actor_type: RepositoryRole
        bypass_mode: pull_request
```

This means a repo can override the base `bypass_actors`
while still contributing extra actors alongside those from
category or org — and vice versa.

### Adding a Team

Create a YAML file in `teams/teams/`:

```yaml
name: my-team
description: My team description.
privacy: closed
notification_setting: notifications_enabled
members:
  - username: octocat
    role: maintainer
  - username: hubot
    role: member
```

See the [`github_team`][tf-team] and
[`github_team_membership`][tf-membership] resource docs
for available fields.

[tf-team]: https://registry.terraform.io/providers/integrations/github/latest/docs/resources/team
[tf-membership]: https://registry.terraform.io/providers/integrations/github/latest/docs/resources/team_membership

### Organization Settings

Org-level settings are declared in
`org-settings/settings.yaml`. Edit the YAML file to change
settings such as default repository permissions, security
scanning defaults, and member privileges. `billing_email`
is injected at plan/apply time from the
`TF_VAR_billing_email` environment variable.

See the [`github_organization_settings`][tf-org] resource
docs for the full list of available fields.

[tf-org]: https://registry.terraform.io/providers/integrations/github/latest/docs/resources/organization_settings

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

Both plan and apply workflows use `generate-matrix.yaml`
to discover Terragrunt units automatically from the
directory structure.

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
