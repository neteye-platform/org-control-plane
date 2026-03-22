# GitHub Organization Control Plane

This repository provides a Terraform managed control plane for GitHub organizations. It uses a YAML-driven approach to manage repositories, teams, and organization settings, with state separation by product group to handle scale and avoid API rate limits.

## Overview

The system uses Terragrunt to orchestrate Terraform modules across multiple state files. Developers define repositories and teams using simple YAML files. These configurations are then merged through a three-tier hierarchy to ensure consistency while allowing specific overrides.

### Architecture

The repository is structured to isolate state and minimize the impact of GitHub API rate limits.

*   **State Separation:** Configurations are split into `teams/`, `org-settings/`, and individual `products/`. Each directory maintains its own Terraform state in S3.
*   **Three-Tier Merge:** Repository settings are calculated by merging three levels of configuration:
    1.  **Org Defaults:** Global settings in `_defaults.yaml`.
    2.  **Product Defaults:** Product group overrides in `products/<name>/_product_defaults.yaml`.
    3.  **Repo Config:** Individual repository overrides in `products/<name>/repos/<repo>.yaml`.
*   **Deep Merge:** The `branch_protection` object undergoes a deep merge to preserve inherited settings (like required approvals) even when specific fields are overridden at the repository level.

```text
org-control-plane/
├── _defaults.yaml          # Layer 1: Global Org Defaults
├── root.hcl                # Shared Terragrunt logic (Backend + Provider)
├── products/               # Layer 2 & 3: Per-Product State
│   └── example-product/
│       ├── _product_defaults.yaml  # Product-level overrides
│       └── repos/
│           ├── service-a.yaml      # Repo-level overrides
│           └── library-b.yaml
├── teams/                  # Global Team Management
└── org-settings/           # Org-wide Settings (Webhooks, Permissions)
```

### Scope Boundaries

Member management (inviting users to the organization or managing individual user roles) is intentionally out of scope for this repository. Identity management should be handled through a centralized SCIM or SAML layer. This control plane focuses on infrastructure resources: repositories, teams, branch protection rules, and organization-level settings.

## Quick Start

### Creating a New Repository

1.  Navigate to your product directory (e.g., `products/my-product/repos/`).
2.  Create a new YAML file named after your repository (e.g., `my-new-app.yaml`).
3.  Add a description (required) and any overrides:

```yaml
description: "High-performance API service for My Product"
visibility: private
teams:
  - name: my-team
    permission: push
topics:
  - api
  - golang
```

4.  Submit a Pull Request. CI will validate your YAML against the schema and run a `terragrunt plan`.

### Creating a New Product Group

1.  Create a new directory in `products/` (e.g., `mkdir -p products/new-product/repos`).
2.  Copy the `terragrunt.hcl` from `products/example-product/terragrunt.hcl`.
3.  (Optional) Create `_product_defaults.yaml` for product-wide overrides.
4.  Add your first repository in `repos/`.

## YAML Reference

### Repository Fields (`repos/*.yaml`)

| Field | Type | Description |
| :--- | :--- | :--- |
| `description` | String | **Required.** Repository description. |
| `name` | String | Repository name. Defaults to the YAML filename if omitted. |
| `visibility` | Enum | `public`, `private`, or `internal`. Defaults to `private`. |
| `auto_init` | Boolean | Automatically initialize with a README. Default: `true`. |
| `teams` | Array | List of `{ name: string, permission: enum }` where permission is `pull`, `push`, `maintain`, `triage`, or `admin`. |
| `branch_protection` | Object | Nested settings for the `main` branch. See below. |
| `webhooks` | Array | List of `{ url, content_type, events, active }`. |
| `autolinks` | Array | List of `{ key_prefix, target_url_template, is_alphanumeric }`. |
| `topics` | Array | List of lowercase alphanumeric topics. Max 20. |
| `has_issues` | Boolean | Enable GitHub Issues. Default: `true`. |
| `allow_squash_merge`| Boolean | Allow squash merges. Default: `true`. |
| `delete_branch_on_merge` | Boolean | Auto-delete branches after merge. Default: `true`. |

#### Branch Protection Settings

These are defined under the `branch_protection` key:

*   `enabled`: (Boolean) Enable protection. Default: `true`.
*   `pattern`: (String) Branch pattern to protect. Default: `main`.
*   `required_approvals`: (Integer) Number of required reviews. Default: `1`.
*   `dismiss_stale_reviews`: (Boolean) Clear reviews on new commits. Default: `true`.
*   `require_code_owner_reviews`: (Boolean) Force code owner sign-off. Default: `false`.
*   `enforce_admins`: (Boolean) Apply rules to admins. Default: `false`.

### Team Fields (`teams/*.yaml`)

| Field | Type | Description |
| :--- | :--- | :--- |
| `description` | String | Team description. |
| `privacy` | Enum | `closed` (visible) or `secret` (hidden). Default: `closed`. |
| `members` | Array | List of `{ username, role }`. Role is `member` or `maintainer`. |
| `parent_team` | String | Name of the parent team for hierarchy. |

## Defaults Hierarchy

This control plane uses a **three-tier merge strategy** to calculate the final configuration for each repository. Settings cascade from organization-wide defaults through product-specific overrides to individual repository configurations.

### Merge Layers

1. **Organization Defaults** (`_defaults.yaml`) — The baseline configuration applied to ALL repositories in the organization
2. **Product Defaults** (`products/<name>/_product_defaults.yaml`) — Optional product-specific overrides that apply to all repos in that product group
3. **Repository Config** (`products/<name>/repos/<repo>.yaml`) — Individual repository overrides with the highest precedence

### How Merging Works

Configuration values flow from org → product → repo, with later layers overriding earlier ones. For example:

```yaml
# _defaults.yaml (Org Layer)
visibility: private
branch_protection:
  required_approvals: 1
  dismiss_stale_reviews: true
  enforce_admins: false

# products/platform/_product_defaults.yaml (Product Layer)
branch_protection:
  required_approvals: 2  # Override org default

# products/platform/repos/api-gateway.yaml (Repo Layer)
description: "Central API Gateway"
visibility: internal  # Override org default
branch_protection:
  required_approvals: 3  # Override product default
```

**Result for `api-gateway` repository:**
- `visibility`: `internal` (from repo layer)
- `branch_protection.required_approvals`: `3` (from repo layer)
- `branch_protection.dismiss_stale_reviews`: `true` (inherited from org layer)
- `branch_protection.enforce_admins`: `false` (inherited from org layer)

### Deep Merge for Branch Protection

**CRITICAL:** The `branch_protection` object uses a **deep merge**, not a shallow replace. This means:

- If you override ONE field in `branch_protection` at the repo level, all other fields are still inherited from the product and org layers
- This prevents accidentally losing security settings when customizing approval counts

**Without deep merge (BAD):**
```yaml
# Repo overrides required_approvals → ALL other branch_protection fields would be lost!
branch_protection:
  required_approvals: 3
# Result: dismiss_stale_reviews, enforce_admins, etc. would become null
```

**With deep merge (GOOD — what we implement):**
```yaml
# Repo overrides required_approvals → other fields inherit from org/product
branch_protection:
  required_approvals: 3
# Result: required_approvals=3, dismiss_stale_reviews=true (from org), etc.
```

This deep merge behavior is explicitly implemented in `modules/github-repos/locals.tf` and is critical for maintaining consistent security baselines across all repositories.

## GitHub App Setup

The control plane authenticates as a GitHub App for higher rate limits (15,000 requests per hour).

### Required Permissions

Ensure your GitHub App has the following permissions:

*   **Repository Permissions:**
    *   `Administration`: Read & Write (settings, branch protection)
    *   `Contents`: Read & Write (initialization, code access)
    *   `Metadata`: Read-only (required)
    *   `Webhooks`: Read & Write
*   **Organization Permissions:**
    *   `Administration`: Read & Write (org-wide settings)
    *   `Teams`: Read & Write (team management)
    *   `Webhooks`: Read & Write

### Configuration Variables

The following variables must be provided via environment variables or a `secrets.tfvars` file:

*   `TF_VAR_github_app_id`: The ID of your GitHub App.
*   `TF_VAR_github_app_installation_id`: The installation ID for your org.
*   `TF_VAR_github_app_pem_file`: Path to the App's private key file.
*   `TF_VAR_github_org`: Your GitHub organization name.

## State Architecture

This control plane uses **separate Terraform state files** for different resource groups instead of managing everything in a single monolithic state. This design choice addresses scale, rate limits, and operational concerns.

### Why Split State?

**1. GitHub API Rate Limit Protection**

GitHub's secondary rate limit restricts REST API operations to 900 points per minute. Each repository creation consumes 5 points. With 100+ repositories:

- **Single state:** 100 repos × 5 pts = 500 pts in ~30 seconds → rate limit hit
- **Split state (4 products):** 25 repos per product × 5 pts = 125 pts per unit → stays under limit

By splitting state across product groups, parallel applies stay within rate limit boundaries even for large organizations.

**2. Blast Radius Reduction**

- Changes to one product's repositories don't risk corrupting state for other products
- Terraform state lock contention is isolated to individual product groups
- Rollback and recovery operations affect only the specific unit that failed

**3. Parallel Development**

Multiple teams can work on different products simultaneously without competing for the same state lock.

### State File Mapping

Each Terragrunt unit maintains its own state in S3:

| Directory | S3 State Key | Manages |
| :--- | :--- | :--- |
| `teams/` | `teams/terraform.tfstate` | All GitHub teams and team memberships |
| `org-settings/` | `org-settings/terraform.tfstate` | Organization-wide settings and webhooks |
| `products/platform/` | `products/platform/terraform.tfstate` | All repos in the "platform" product group |
| `products/data-eng/` | `products/data-eng/terraform.tfstate` | All repos in the "data-eng" product group |

The state key pattern is generated automatically using `path_relative_to_include()` in `root.hcl`, ensuring each unit gets a unique S3 key based on its directory path.

### Cross-Unit Dependencies

Teams must exist before repositories can reference them for access control. This is enforced via Terragrunt dependency blocks:

```hcl
# products/platform/terragrunt.hcl
dependency "teams" {
  config_path = "../../teams"
  skip_outputs = true  # We only need ordering, not data
}
```

When running `terragrunt run-all plan`, Terragrunt automatically:
1. Plans `teams/` first
2. Plans `org-settings/` (no dependency)
3. Plans all `products/*` units in parallel (after teams completes)

This ensures `data.github_team` lookups in the repos module never fail due to missing teams.
## Running Locally

### Prerequisites

*   Terraform >= 1.5
*   Terragrunt >= 0.50
*   AWS credentials (for S3 state backend)

### Commands

Run a plan across the entire organization:

```bash
terragrunt run --all plan
```

Target a specific product group:

```bash
cd products/my-product
terragrunt plan
```

**Note:** Use `TG_PARALLELISM=3` to avoid hitting GitHub secondary rate limits during large runs.

## Troubleshooting

### Rate Limits (429 Errors)

We use a `write_delay_ms = 1000` in the provider configuration to stay under GitHub's secondary rate limits (900 points per minute). If you encounter rate limit errors, Terragrunt is configured to retry with an exponential backoff.

### Repository Already Exists

The CI pipeline includes a script to detect duplicate repository names across different product groups. If you get a 422 error from the GitHub API, check if another product has already defined a repository with the same filename.

### Branch Protection Fails

Branch protection requires at least one commit in the repository. We set `auto_init: true` by default to ensure the `main` branch exists immediately. If you disable `auto_init`, you must manually push a commit before Terraform can apply branch protection rules.
