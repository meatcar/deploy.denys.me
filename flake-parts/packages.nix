{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      packages =
        lib.optionalAttrs pkgs.stdenv.isLinux {
          cli-proxy-api-ops = import ../packages/cli-proxy-api/package.nix { inherit pkgs; };
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          doImage = self.nixosConfigurations.doImage.config.system.build.image;
          baoImage = self.nixosConfigurations.bao.config.system.build.images.openstack;
          baoInstaller = pkgs.nixos-anywhere.overrideAttrs (old: {
            # NOTE: Upstream disables host verification before applying CLI SSH options.
            # see https://github.com/nix-community/nixos-anywhere/issues/552
            postPatch = (old.postPatch or "") + ''
              substituteInPlace src/nixos-anywhere.sh \
                --replace-fail 'UserKnownHostsFile=/dev/null' 'UserKnownHostsFile=''${NIXOS_ANYWHERE_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}' \
                --replace-fail 'StrictHostKeyChecking=no' 'StrictHostKeyChecking=yes'
            '';
          });
        };
    };
}
