{ ... }:
let
  inherit (builtins) getEnv;
in
{
  mine = {
    znc.users.meatcar = {
      password = getEnv "TF_VAR_nix_znc_password";
      # echo pass\npass | nix-shell -p znc --command 'znc --makepass'
      hash = getEnv "TF_VAR_nix_znc_hash";
      salt = getEnv "TF_VAR_nix_znc_salt";
      networks.freenode.nickservPassword = getEnv "TF_VAR_nix_znc_salt";
    };
  };
}
