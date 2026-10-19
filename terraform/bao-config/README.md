# Bao configuration

One state owns auth, policies and project mounts. Use the
[root workflow](../README.md#plan-and-apply) with `-chdir=terraform/bao-config`.
This root requires human authority and must not run under agent plan credentials.

## Project access

Add one entry to `projects` in [projects.tf](projects.tf). The
[child module](modules/project-layout) creates a protected KV v2 mount,
exact-path read policies for non-empty credential sets, and only explicitly
granted Amp plan roles. It does not create or read secret values.

- Project names are literal lower-case `owner/repository` pairs. Credential names
  use literal slash-separated segments. No wildcards, templates or normalization.
- Environments are `dev` and `prod`; classes are `plan`, `inference` and `admin`.
  Omitted or empty classes create no policy. Amp grants are only `dev/plan` or
  `prod/plan`, each backed by a non-empty plan set.
- Root preconditions reject mount/policy/role namespace collisions and duplicate
  Amp IDs, including ambiguous `--` joins even with different credential sets.
  Policies use `allow_overwrite = false`. Existing reserved names require review
  and explicit import, not automatic adoption. Mount renames require migration.
- Module outputs `mount`, `secret_keys`, `policy_names` and `role_names` contain
  only locations and names. Read exact data paths, not metadata or mount listings.

The initial entry grants `meatcar/deploy.denys.me` only `prod/plan`, with the
personal Amp project ID and subject. There is no `workspace_id` binding.
`auth/amp` uses Amp's issuer discovery and RS256. Roles require audience `bao`,
the exact project-scope subject, matching `project_id`, `token_use=exchanged` and a
present `thread_id`, which setup tokens lack.
Tokens receive one plan policy, no default policy, and a hard five-minute lifetime.
No setup, inference, admin or GitHub authentication grants are installed.
Every orb of this Amp project can select its plan role; the environment label
does not establish an Amp environment. Review the subject if the project moves.

CLIProxyAPI's existing mount, policies, rotation and deployment resources are
unchanged. Its migration to this layout is separate from this module's installation.

## Verification and live rollout

The root's `*.tftest.hcl` files use mocked Vault providers. The Terraform flake
check runs them, including child-module tests selected by each run's `module`
block. Checks assert exact ACLs/bindings and reject malformed names, injection,
collisions and unauthorized grant classes. Mocks cannot prove server-side policy
collision refusal, JWT login or ACL enforcement.

Before a human-approved live apply:

1. Renew AWS SSO and connect to Bao. Inventory `projects/` mounts, reserved
   `project--` policies and attachments, existing `auth/amp` configuration and
   effective identity/group policies. Resolve unexpected names; review and import
   approved existing resources explicitly. Never overwrite an unmanaged policy.
2. Review a live plan. It must preserve CLIProxyAPI, existing human `admin`, AWS
   `terraform-admin` and userpass recovery. Apply only after approval. Confirm
   pinned Vault provider 5.12.0 compatibility with OpenBao and Bao's outbound
   HTTPS access to Amp's discovery/JWKS endpoints. Discovery was checked publicly;
   server reachability and compatibility have not been tested live.
3. Once orbs can reach Bao, use disposable non-secret canaries and real orb JWTs.
   The declared plan read must succeed. Deny another project/environment,
   inference/admin and pending keys, legacy `kv`, metadata/list, all writes and
   token creation. Wrong audience, subject/project, setup tokens and unlisted
   roles must fail login. Audit effective token and identity policies, not just
   role policies. Do not attach identity/group policies to these entities.
4. Independently verify each provider credential's read-only authority,
   secret-reading limits and path history before publication. Policies can exist
   while their declared documents are absent. Never fall back to operator tokens.
