{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "vpn-bao-isolation";
  nodes.server =
    { ... }:
    {
      imports = [ ./firewall.nix ];
      networking.dhcpcd.denyInterfaces = [
        "wt0"
        "pub0"
      ];
      environment.systemPackages = with pkgs; [
        curl
        iproute2
        iptables
        python3
      ];
      systemd.services.test-listener = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 443 --bind ::";
      };
    };
  testScript = ''
    server.start()
    server.wait_for_unit("firewall.service")
    server.wait_for_unit("test-listener.service")
    for name, interface, subnet in [("private", "wt0", 1), ("public", "pub0", 2)]:
        server.succeed(f"ip netns add {name}")
        server.succeed(f"ip link add {interface} address 02:00:00:00:{subnet:02x}:01 type veth peer name peer address 02:00:00:00:{subnet:02x}:02 netns {name}")
        server.succeed(f"ip addr add 192.0.{subnet}.1/24 dev {interface}")
        server.succeed(f"ip -6 addr add fd00:{subnet}::1/64 dev {interface} nodad")
        server.succeed(f"ip link set {interface} up")
        server.succeed(f"ip -n {name} addr add 192.0.{subnet}.2/24 dev peer")
        server.succeed(f"ip -n {name} -6 addr add fd00:{subnet}::2/64 dev peer nodad")
        server.succeed(f"ip -n {name} link set peer up")
        server.succeed(f"ip -n {name} link set lo up")
    server.succeed("ip netns exec private curl --noproxy '*' -fsS --max-time 3 http://192.0.1.1:443/ > /dev/null")
    server.succeed("ip netns exec private curl --noproxy '*' -gfsS --max-time 3 http://[fd00:1::1]:443/ > /dev/null")
    for tool in ["iptables", "ip6tables"]:
        server.succeed(f"{tool} -I INPUT -p tcp --dport 443 -j ACCEPT")
    server.fail("ip netns exec public curl --noproxy '*' -fsS --max-time 3 http://192.0.2.1:443/")
    server.fail("ip netns exec public curl --noproxy '*' -gfsS --max-time 3 http://[fd00:2::1]:443/")
    server.succeed("systemctl stop firewall")
    server.fail("ip netns exec public curl --noproxy '*' -fsS --max-time 3 http://192.0.2.1:443/")
    server.succeed("systemctl restart firewall")
    server.succeed("ip netns exec private curl --noproxy '*' -fsS --max-time 3 http://192.0.1.1:443/ > /dev/null")
    server.fail("ip netns exec public curl --noproxy '*' -fsS --max-time 3 http://192.0.2.1:443/")
  '';
}
