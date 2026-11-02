{ lib, pkgs, ... }:
let
  bao-sync = import ../../../packages/bao-sync/package.nix { inherit pkgs; };
  token = "/etc/vpn/bao-sync-token";
  # NOTE: plan reads every synced folder each run; run it by hand, time only apply.
  apply = false;
in
{
  systemd.services.bao-sync = {
    description = "Sync Bao secrets to hosting providers";
    after = [ "openbao.service" ];
    unitConfig.ConditionPathExists = token;
    environment = {
      BAO_ADDR = "https://bao.vpn.denys.me";
      BAO_SYNC_TOKEN_FILE = "%d/token";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${bao-sync}/bin/bao-sync ${if apply then "apply" else "plan"}";
      LoadCredential = "token:${token}";
      DynamicUser = true;
      StateDirectory = "bao-sync";
      TimeoutStartSec = "5m";
      CapabilityBoundingSet = "";
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      PrivateUsers = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" ];
      UMask = "0077";
    };
  };
  systemd.timers.bao-sync = {
    wantedBy = lib.optional apply "timers.target";
    timerConfig = {
      OnBootSec = "2m";
      OnUnitInactiveSec = "1m";
    };
  };
}
