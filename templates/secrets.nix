{ ... }: {
  config.mine = {
    znc.users.meatcar = {
      password = "${password}";
      # echo pass\npass | nix-shell -p znc --command 'znc --makepass'
      hash = "${hash}";
      salt = "${salt}";
      networks.freenode.nickservPassword = "${nickservPassword}";
    };
  };
}
