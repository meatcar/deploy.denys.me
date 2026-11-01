{ pkgs }:
let
  # Exercise the files mounted by the production Quadlet, not a second policy.
  module = import ./traefik.nix {
    inherit pkgs;
    config = {
      mine = {
        persistPath = "/test";
        notificationEmail = "test@example.invalid";
      };
      age.secrets.cloudflareToken.path = "/unused";
      home-manager.users.pod.virtualisation.quadlet.networks.proxy.ref = "proxy.network";
    };
  };
  mounts =
    module.home-manager.users.pod.virtualisation.quadlet.containers.traefik.containerConfig.volumes;
  mounted =
    target:
    builtins.head (
      pkgs.lib.splitString ":" (
        builtins.head (builtins.filter (mount: pkgs.lib.hasInfix ":${target}:" mount) mounts)
      )
    );
  invoice =
    (import ./invoiceninja {
      inherit pkgs;
      config.home-manager.users.pod.virtualisation.quadlet.volumes = {
        invoiceninja-public.ref = "public.volume";
        invoiceninja-storage.ref = "storage.volume";
      };
    }).home-manager.users.pod.virtualisation.quadlet.containers;
  invoiceMount =
    container: target:
    builtins.head (
      pkgs.lib.splitString ":" (
        builtins.head (
          builtins.filter (
            mount: pkgs.lib.hasInfix ":${target}:" mount
          ) invoice.${container}.containerConfig.volumes
        )
      )
    );
  applicationRoutes = pkgs.writeText "application-routes.json" (
    builtins.toJSON (
      pkgs.lib.recursiveUpdate (import ./larapaper/routes.nix) (import ./invoiceninja/routes.nix)
    )
  );
  cpaRoutes = pkgs.writeText "cpa-routes.json" (
    builtins.toJSON (
      import ./cli-proxy-api/routes.nix {
        publicHost = "cpa.pvlv.ca";
        managementHost = "cpa.vpn.denys.me";
      }
    )
  );
  niks3Routes = pkgs.writeText "niks3-routes.json" (
    builtins.toJSON (
      import ../niks3/routes.nix {
        host = "cache.denys.me";
        port = "5751";
      }
    )
  );
in
pkgs.runCommand "application-routing"
  {
    passthru = {
      staticConfig = mounted "/etc/traefik/traefik.yml";
      dynamicConfig = applicationRoutes;
    };
    nativeBuildInputs = [
      pkgs.traefik
      pkgs.php
      pkgs.nginx
      (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
    ];
  }
  ''
    python ${./test_routing.py} \
      ${mounted "/etc/traefik/traefik.yml"} \
      ${applicationRoutes} \
      ${invoiceMount "invoiceninja-nginx" "/etc/nginx/conf.d/default.conf"} \
      ${pkgs.nginx}/conf/fastcgi_params ${./test_invoice_front_controller.php} \
      ${cpaRoutes} ${niks3Routes}
    touch "$out"
  ''
