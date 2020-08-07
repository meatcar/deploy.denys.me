{ config, pkgs, ... }: {
  systemd.tmpfiles.rules = [
    "L /var/lib/deluge - - - - ${config.persistPath}/var/lib/deluge"
  ];

  services.deluge =
    let
      authFile = pkgs.writeTextFile {
        name = "authFile";
        text = "localclient:deluge:10\n";
      };
    in
    {
      enable = true;
      dataDir = "${config.persistPath}/var/lib/deluge";
      declarative = true;
      authFile = authFile;
      extraPackages = with pkgs; [ unzip gnutar xz p7zip bzip2 ];
      config = {
        allow_remote = true;
        move_completed = true;
        move_completed_path = "${config.storagePath}/System/deluge/completed";
        download_location = "${config.storagePath}/System/deluge/inprogress";
        share_ratio_limit = "1.0";
        enc_level = "2"; # full stream
        enabled_plugins = [ "Label" "Extractor" ];
      };
      web = {
        enable = true;
        openFirewall = false;
      };
    };

  services.nginx.virtualHosts."deluge.${config.fqdn}" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:8112";
  };
}
