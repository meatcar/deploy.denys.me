{ pkgs, ... }:
{
  systemd.tmpfiles.rules = [
    "d /persist/murmur 0700 murmur nogroup -"
    "L /var/lib/murmur - - - - /persist/murmur"
  ];

  services.murmur = {
    enable = true;
    welcometext = ''
      <br />Welcome to <i>mumble.denys.me</i>!
      <br />Be nice, and enjoy your stay! :) :) :D
      <br /><h3>NOTICE</h3> This server has moved to <u>mumble.denys.me</u>.
      <br />Please let your friends know :)
    '';
  };
  networking.firewall.allowedTCPPorts = [ 64738 ];
  networking.firewall.allowedUDPPorts = [ 64738 ];

  docker-containers.mumbledj = {
    image = "reikion/mumbledj";
    volumes = [
      "/persist/mumbledj/config.yaml:/home/mumbledj/.config/mumbledj/config.yaml"
    ];
  };
}
