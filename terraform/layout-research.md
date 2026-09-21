# Terraform layout options

Historical research, superseded by the decision to use native modules and two
deployment roots. See [the current workflow](README.md).

Research date: 2026-09-21. Proposal only; no infrastructure or state changes.
Local tools: Terragrunt 1.0.4 and OpenTofu 1.11.8.

## What the sources establish

- OpenTofu recommends flat module composition: modules receive dependencies from their caller instead of creating their own copies. This supports host-composed or service-composed roots. It does not prescribe state ownership. [OpenTofu 1.11 composition](https://opentofu.org/docs/v1.11/language/modules/develop/composition/)
- HashiCorp scopes modules by resources deployed together, privileges, and volatility. Those considerations also inform which root configurations should be independently operated; child modules alone do not isolate state. [Module creation guidance](https://developer.hashicorp.com/terraform/tutorials/modules/pattern-module-creation)
- A Terragrunt unit is an independently deployable configuration. Stacks collect units; they do not merge their states or provide a cross-state transaction. Each unit needs a distinct backend identity. [Units](https://docs.terragrunt.com/features/units/), [stacks](https://docs.terragrunt.com/features/stacks/), [backend key collisions](https://docs.terragrunt.com/getting-started/overview/)
- Implicit stacks are ordinary directories of units. Official guidance recommends them for unique deployments and explicit `terragrunt.stack.hcl` stacks for repeated collections. "Start with implicit stacks ... then gradually introduce explicit stacks for reusable patterns." [Stack selection](https://docs.terragrunt.com/features/stacks/)
- Gruntwork's catalog separates reusable modules, units, and stacks. Its guidance is to introduce stacks once a deployment pattern is proven. The current catalog requires Terragrunt 1.1, newer than this repository's installed version. Basic stack commands are available locally, but newer catalog features should not be copied unchanged. [Catalog](https://github.com/gruntwork-io/terragrunt-infrastructure-catalog-example)
- The first-party live example uses account/region/resources and explicitly targets AWS. This is evidence for organizing by administrative scope, not a requirement for this multi-cloud repository. [Live example](https://github.com/gruntwork-io/terragrunt-infrastructure-live-stacks-example)

## Local observations

- Six current roots combine a mixed legacy root with `bao`, `bao-config`, `netbird`, `ovh-vps`, and `railway`. All configure explicit S3 backend keys.
- The legacy root includes backend provisioning, two hosts, public DNS, and WireGuard key/config generation.
- `bao-config/terragrunt.hcl` uses ordering-only `dependencies` for Bao infrastructure and NetBird; it does not pass their outputs.
- DNS mixes shared zone configuration, service records, mail records, and zone-wide rules. Multiple service records repeat the same origin IP.
- `nixos/systems/chunkymonkey/configuration.nix` imports the shared Quadlet module, which imports all workloads together. Independent host selection needs a NixOS composition change regardless of Terraform layout.
- Existing Nix checks discover Terraform roots with lockfiles and run Terragrunt validation. Explicit stack generation would need integration into those checks.

## Option 1: Administrative/provider units

Organize independent plans around the systems being administered. Keep service-specific files inside those units.

```text
terraform/live/
  cloudflare/domains/
  cloudflare/records/
  oci/toronto/compute/
  digitalocean/toronto/compute/
  ovh/compute/
  aws/state/
  aws/bao-support/
  netbird/access/
  bao/config/
  railway/projects/
```

Each leaf is a unit. This is a small multi-cloud adaptation of account/region-oriented layouts, not a literal copy of the AWS example.

- Cloudflare owns public DNS and zone rules. Service records can live in `billing.tf`, `monitor.tf`, etc.
- Bao spans OVH hosting, AWS support, Bao configuration, and NetBird access. Monitoring's runtime remains in Railway.
- Moving a NixOS service changes host imports and DNS inputs, but does not transfer its Cloudflare record between states.
- Terragrunt shares provider/backend configuration through includes and passes host outputs to DNS using `dependency` blocks.
- Best when credential scope and provider administration dominate. State separation only enables narrower permissions; access controls must enforce them.
- Cost: one service remains spread across administrative units. DNS and Railway plans grow with the fleet, and independent services share their locks.

## Option 2: Host/deployment bundles

Let a deployment root compose compute and the Terraform resources of the services assigned to it. Reuse shallow child modules that accept host/zone inputs.

```text
terraform/
  modules/services/billing/
  modules/services/paseo/
  live/shared/domains/
  live/shared/netbird/
  live/deployments/chunkymonkey/
  live/deployments/www/
  live/deployments/bao-host/
  live/deployments/railway-monitor/
  live/bao-support/
  live/bao-config/
```

Each live leaf is a unit. Service modules instantiated inside a deployment belong to that deployment's state. Shared zones and Bao prerequisites remain separate.

- `chunkymonkey` composes its machine and billing/Paseo DNS or other service-specific external resources. NixOS separately composes runtime modules.
- Monitor is a Railway deployment bundle, not a fictional VM. Bao configuration remains separate from the host and bootstrap prerequisites.
- Terragrunt runs a small number of coarse units. OpenTofu resolves dependencies within each bundle in one plan.
- Best when machines are durable appliances and most changes concern the complete host.
- Cost: service changes share a plan and lock with the host. Moving a service's child module to another host root also changes its state owner. Reusing source code does not transfer ownership of existing DNS, IAM, or storage resources; migration must preserve those objects explicitly.

## Option 3: Stable service units with separate placement

Give service infrastructure an identity independent of its current host. Group related units under the service name, splitting only where lifecycle or credentials require it.

```text
terraform/live/
  shared/domains/
  shared/netbird/
  shared/state/
  hosts/chunkymonkey/
  hosts/www/
  hosts/bao/
  services/bao/support/
  services/bao/config/
  services/billing/
  services/paseo/
  services/monitor/
```

Each leaf is a unit. `services/bao/` is a grouping directory, not an additional state.

- Hosts own compute and host-specific networking. Services own their individual public DNS records and external resources. Shared domains own zones and zone-wide rulesets.
- Billing consumes its destination host address through Terragrunt. A host move changes the placement reference without changing the billing unit's backend identity.
- Bao has the same service status as monitor, with separate support/config units for bootstrap and recovery. No foundation-versus-app classification is required.
- Monitor owns its Railway deployment. Its target list remains explicit and need not include every service. No new monitoring integration is implied.
- NixOS hosts still import runtime modules. Avoid a host-to-service Terraform dependency that reverses the service-to-host edge. Host selection does not need to be implemented through Terraform state.
- Best when services should outlive machines or move independently.
- Cost: more units and output contracts. Upstream changes require downstream re-planning. Moving stateful data or switching Railway to NixOS still requires a migration; stable Terraform identity only removes unnecessary ownership transfers for retained resources.

## Recommendation

Choose option 3 for the stated relocation goal, using ordinary implicit stacks initially. Option 1 is preferable if the priority is provider access isolation with fewer operating units. Option 2 most directly mirrors host imports, but couples service infrastructure ownership to hosts.

Use explicit stacks later when a repeated collection of units is worth generating, such as multiple deployments of the same service pattern. Explicit stacks can support any of these ownership models; they are not a fourth model. Keep modules and live configuration in this repository while they evolve together.

## Constraints for any implementation

1. Preserve explicit backend keys during directory-only moves. Path-derived keys such as `path_relative_to_include()` change when directories move. Explicit stacks default to generated `.terragrunt-stack/<path>` directories, which also affect path-derived keys. Do not silently replace the current stable keys with a path convention. [Overview](https://docs.terragrunt.com/getting-started/overview/), [explicit stacks](https://docs.terragrunt.com/features/stacks/explicit/)
2. `dependency` retrieves applied outputs and adds ordering. `dependencies` adds ordering only. Planning upstream does not publish its proposed outputs to downstream plans. Apply upstream changes, then regenerate dependent plans. Mocks permit structural previews but can be embedded in saved plans; those plans are not safe substitutes for plans using actual outputs. [Block reference](https://docs.terragrunt.com/reference/hcl/blocks/#dependency), [run queue](https://docs.terragrunt.com/features/stacks/run-queue/)
3. Treat directory moves, resource-address changes, and cross-state extraction as separate operations. `init -migrate-state` copies backend state; `-reconfigure` explicitly avoids migration. Neither a new directory nor a stack definition transfers resource ownership automatically. [OpenTofu init](https://opentofu.org/docs/v1.11/cli/commands/init/), [state mv](https://opentofu.org/docs/v1.11/cli/commands/state/mv/)
4. Keep Bao bootstrap and recovery credentials independent of Bao itself. Directory ordering cannot resolve a circular bootstrap dependency.
5. Keep public zone-wide rulesets and complete NetBird group memberships under single owners. Per-service discovery does not justify competing owners of a shared provider object.

Verification was limited to source/configuration inspection and local version/help commands. No live plans, credentials, secret files, or remote state were read.
