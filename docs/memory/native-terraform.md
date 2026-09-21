---
name: native-terraform
description: Native Terraform composition and minimal state separation are explicit user preferences.
metadata:
  type: feedback
---

Prefer native Terraform/OpenTofu modules and the fewest practical states.
Terragrunt is only useful here as a root-level bulk runner.

**Why:** The user wants portable service configuration without adopting a
Terragrunt-specific infrastructure framework.

**How to apply:** Keep resource composition, inputs, and outputs native.
Introduce a separate state for a concrete operational prerequisite, not for
each provider, host, service, or reusable module.
