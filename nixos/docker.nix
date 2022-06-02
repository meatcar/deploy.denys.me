{ pkgs, ... }:
{
  virtualisation.oci-containers.backend = "docker";
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  environment.systemPackages = with pkgs; [
    kube3d
    kompose
    kubectl
  ];
}
