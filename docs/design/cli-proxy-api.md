# CLIProxyAPI credential design

## Admin credential rotation

Terraform owns the Bao read policy, not the Manager Plus admin credential. An
operator is the only party connected to both Bao and `chunkymonkey`. The host
has no Bao token, and Bao has no SSH credential for the host.

Each generation has one candidate stored with Bao compare-and-set semantics.
Retries reuse that candidate. The operator sends it over host-key-checked SSH,
the host resets and verifies the local login, the operator verifies rejection
of the old key, and only then publishes the new value. This ordering creates a
short publication gap but never leaves the old credential valid after a
successful reset.

The host keeps a private, fsynced rotation record. A systemd recovery hook uses
the pinned Manager Plus image's offline reset command before startup. This lets
the host recover after reboot or database restoration without Bao, AWS SSO, or
an operator workstation. The rotation record and manager database form one
recovery unit.

Rotation never restores the entire database. A database rollback could discard
usage and configuration changes. A failed reset blocks Manager Plus startup;
the operator fixes the cause and retries the same generation.

Manager Plus has no suitable authenticated online rotation API. If upstream
adds a retry-safe API, it can replace the offline reset while keeping the same
Bao staging and publication rules.

## Credential separation

The Manager Plus admin key, CLIProxyAPI service management key, and inference
keys are separate credentials. Admin rotation does not change the other two.
The dev inference policy cannot read the production admin secret or its pending
document.

Terraform's existing inference-key ownership is unchanged. It stages a key,
deploys and verifies it, then publishes it. Existing keys are not automatically
revoked, because consumers need time to switch. No second writer may replace
the full key list; that could delete enrolled client keys.

Secret values stay out of Terraform state, the Nix store, command arguments,
and command output. No custom OpenBao secrets engine, OIDC trust, or orb
connectivity is installed.
