# Orb access overlay

Task-based setup/resume for an existing Nix flake and direnv project. Requires
disposable Debian Linux with systemd, sudo, Bash, curl, CA certificates, tar,
gzip and coreutils. Task bootstrap supports x86_64 and aarch64. Kernel-mode
NetBird needs `/dev/net/tun` and network administration privileges.

## Install

```sh
nix flake init -t github:meatcar/deploy.denys.me#orb-access
chmod +x .agents/setup .agents/resume
```

The template is an interim home in deploy.denys.me. Template export does not
preserve executable bits. Reconcile existing `.agents` files before installation.
It adds no root Taskfile, flake input, or `.envrc`.

Supply `netbird`, `openbao`, `jq`, and `go-task` in the project's Linux devshell.
Set `BAO_ROLE` in `.agents/Taskfile.yml`'s `env` to the project's approved JWT role.
`BAO_ADDR` defaults to `https://bao.vpn.denys.me`.
Store `NETBIRD_SETUP_KEY` as an Amp **project secret**, restricted to that
project's ephemeral orb group. `NETBIRD_MANAGEMENT_URL` defaults to NetBird Cloud.

Customize `.agents/Taskfile.yml`; replace `sandbox/` and `access/` together when
updating shared behavior. `sandbox/` derives from
[nix-templates sandbox](https://github.com/meatcar/nix-templates/tree/301e06778d5ff54540a767d362ce623509df0ea2/templates/sandbox).

## Lifecycle

- `.agents/setup` bootstraps checksum-verified Task 3.48.0, Nix and direnv,
  installs login-shell activation, and configures a dedicated NetBird daemon.
  It never enrolls or logs into Bao. Put credential-free dependency preparation
  in `work`, which also runs on resume.
- `.agents/resume` starts the daemon and enrolls only when disconnected. The
  setup key passes through a mode-0600 file in `/run`, removed on success or
  failure. Inbound traffic and client/server routes are disabled. No netstack.
  The daemon is not enabled at boot; each resume starts it explicitly.
  CLI calls time out after 60 seconds. Amp waits only 10 seconds for resume;
  check its resume log before using Bao if enrollment is still running.
- `setup_cleanup` stops the daemon, removes its `/run` state and temporary key
  directory, Bao/Vault token files, and AWS CLI/SSO caches. The launcher runs it
  outside the devshell on setup success or failure. Cleanup failure fails setup.
  Forced termination can prevent cleanup. Setup itself creates no credentials.

The launcher, future login shells, and Bao helper add the Bao hostname to both
`NO_PROXY` and `no_proxy`, retaining existing exclusions and HTTPS proxy settings.
Task commands run in separate shells; exports in one task do not reach another.

## On-demand Bao access

```sh
task --dir . --taskfile .agents/Taskfile.yml access:bao -- \
  bao kv get -mount=projects/OWNER/PROJECT prod/plan/PROVIDER
```

This mints `amp orb id-token --audience bao --subject-scope project`, exchanges
it at `auth/amp/login`, and gives only the child command `BAO_TOKEN`. Neither
token is written to disk or passed in command arguments. There is no login
cache or renewal. Invoke again after the five-minute role token expires.
Authentication failure prevents the child command. Avoid tracing or printing
the child's environment. This command works only in an Amp orb.

These scripts provide convenience, not authorization. Any project orb can
extract the setup key and call Bao directly. NetBird policies, Bao JWT bindings
and provider credential scope enforce access. Key expiry/revocation does not
evict enrolled peers.

See Amp's [lifecycle](https://ampcode.com/docs/orbs/customizing) and
[OIDC](https://ampcode.com/docs/orbs/handling-secrets) documentation. Before use,
verify fresh and resumed orb enrollment, DNS/TLS and proxy bypass, access denials,
OIDC claims, token expiry, and clean snapshot restoration. Offline fixtures do
not prove these. Provisioning and a plan task are separate.
