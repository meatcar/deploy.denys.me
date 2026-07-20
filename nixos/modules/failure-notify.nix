# Email notification for systemd units that fail silently.
#
# Backups, scrubs and GC only ever run unattended, so a failure is invisible
# until someone happens to look. This attaches an OnFailure= handler to the
# units that matter and mails the journal tail.
#
# It is opt-in and asserts that a mail relay actually exists, because alerting
# that silently cannot send is worse than none: it invites the assumption that
# no mail means no failures.
#
# Credentials never enter the nix store. msmtp reads /etc/msmtprc, which
# modules/smtp.nix renders at activation time from an agenix secret.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mine.failureNotify;
in
{
  options.mine.failureNotify = {
    enable = lib.mkEnableOption "email notification when key systemd units fail";

    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "restic-backups-persist"
        "zfs-scrub"
      ];
      description = ''
        Service names to attach a failure notification to, without the
        `.service` suffix.
      '';
    };

    to = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = ''
        Recipient address. The default relies on the root alias that
        modules/smtp.nix writes to /etc/msmtp-aliases.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.programs.msmtp.enable;
        message = ''
          mine.failureNotify.enable needs a working mail relay, but
          programs.msmtp is not enabled on ${config.networking.hostName}.
          Import modules/smtp.nix and set mine.smtp.* first.
        '';
      }
    ];

    systemd.services =
      # Attach the handler to each requested unit...
      lib.genAttrs cfg.units (name: {
        onFailure = [ "notify-failure@${name}.service" ];
      })
      // {
        # ...and define the handler once, as a template whose %i is the name of
        # the unit that failed.
        "notify-failure@" = {
          description = "Notify that %i failed";
          # No Install section: only ever pulled in by OnFailure=.
          serviceConfig = {
            Type = "oneshot";
            # A hung notifier must not wedge whatever triggered it.
            TimeoutStartSec = "2m";
          };
          path = [
            pkgs.systemd
            pkgs.coreutils
          ];
          scriptArgs = "%i";
          script = ''
            unit="$1.service"
            {
              echo "Subject: [${config.networking.hostName}] $unit failed"
              echo "To: ${cfg.to}"
              echo
              echo "$unit failed on ${config.networking.hostName} at $(date -Is)."
              echo
              echo "--- systemctl status ---"
              systemctl status --full --no-pager "$unit" 2>&1 | head -50
              echo
              echo "--- last 50 journal lines ---"
              journalctl --unit "$unit" --no-pager --lines 50 2>&1
            } | ${pkgs.msmtp}/bin/msmtp --read-recipients --read-envelope-from
          '';
        };
      };
  };
}
