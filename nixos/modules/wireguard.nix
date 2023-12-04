{ lib, ... }:
{
  options.mine.networking.wireguard = {
    ipIndex = lib.mkOption {
      type = lib.types.int;
      description = "The last number of the wireguard ip address of the machine.";
      default = 1;
    };
    serverPort = lib.mkOption {
      type = lib.types.int;
      description = "The server's wireguard port";
      default = 51820;
    };
  };
  config = {
    networking.wireguard.enable = true;
  };
}
