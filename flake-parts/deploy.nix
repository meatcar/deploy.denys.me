{ inputs, self, ... }:
{
  flake.deploy = {
    sshUser = "meatcar";
    user = "root";
    remoteBuild = true;
    fastConnection = true;

    nodes = {
      bao = {
        hostname = "51.222.84.199";
        sshUser = "root";
        sshOpts = [
          "-o"
          "StrictHostKeyChecking=yes"
          "-o"
          "IdentityAgent=~/.1password/agent.sock"
          "-o"
          "UserKnownHostsFile=output/ovh-bao-vps/bao-known_hosts"
        ];
        profiles.system.path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.baoVps;
        remoteBuild = false;
      };
      chunkymonkey = {
        hostname = "chunkymonkey.fish-hydra.ts.net";
        profiles.system.path = inputs.deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.chunkymonkey;
      };
      vps = {
        hostname = "to.fish-hydra.ts.net";
        profiles.system.path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.vps;
        remoteBuild = false;
      };
      cube = {
        hostname = "cube.fish-hydra.ts.net";
        profiles.system.path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.cube;
      };
    };
  };
}
