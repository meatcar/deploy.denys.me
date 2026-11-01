{ pkgs }:
let
  certificate =
    pkgs.runCommand "private-access-test-certificate" { nativeBuildInputs = [ pkgs.openssl ]; }
      ''
        mkdir "$out"
        openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=example.test \
          -keyout "$out/key.pem" -out "$out/cert.pem"
      '';
  tls = {
    forceSSL = true;
    sslCertificate = "${certificate}/cert.pem";
    sslCertificateKey = "${certificate}/key.pem";
  };
in
pkgs.testers.runNixOSTest {
  name = "private-access-isolation";
  nodes = {
    server =
      { lib, ... }:
      {
        imports = [
          ../nginx.nix
          ./.
        ];
        mine.privateAccess = {
          httpHosts = [ "private.example.test" ];
          tcpPorts = [ 7000 ];
        };
        networking.dhcpcd.denyInterfaces = [
          "wt0"
          "tailscale0"
          "pub0"
        ];
        services.nginx.virtualHosts = {
          "public.example.test" = tls // {
            locations."/".return = "200 public-content";
          };
          "private.example.test" = tls // {
            locations."/".return = "200 private-content";
          };
        };
        environment.systemPackages = with pkgs; [
          curl
          iproute2
          iptables
          socat
        ];
        systemd.services =
          lib.genAttrs [ "probe-22" "probe-7000" ] (name: {
            wantedBy = [ "multi-user.target" ];
            serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${lib.removePrefix "probe-" name} --bind ::";
          })
          // {
            udp-60000 = {
              wantedBy = [ "multi-user.target" ];
              serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${./udp-echo.py} 60000";
            };
          };
      };
  };
  testScript = ''
    start_all()
    server.wait_for_unit("nginx.service")
    for subnet, (name, interface) in enumerate([("private", "wt0"), ("public", "pub0"), ("relay", "tailscale0")], 1):
        server.succeed(f"ip netns add {name}")
        server.succeed(f"ip link add {interface} type veth peer name peer netns {name}")
        server.succeed(f"ip addr add 192.0.{subnet}.1/24 dev {interface}; ip link set {interface} up")
        server.succeed(f"ip -6 addr add fd00:{subnet}::1/64 dev {interface} nodad")
        server.succeed(f"ip -n {name} addr add 192.0.{subnet}.2/24 dev peer; ip -n {name} link set peer up; ip -n {name} link set lo up")
        server.succeed(f"ip -n {name} -6 addr add fd00:{subnet}::2/64 dev peer nodad")
    for port in [22, 7000]:
        server.wait_for_unit(f"probe-{port}.service")
    server.wait_for_unit("udp-60000.service")

    def network_cases():
        for subnet, name in enumerate(["private", "public", "relay"], 1):
            for address in [f"192.0.{subnet}.1", f"[fd00:{subnet}::1]"]:
                prefix = f"ip netns exec {name} curl --noproxy '*' -gkfsS --max-time 2"
                private = f"{prefix} --resolve private.example.test:443:{address} https://private.example.test/ | grep -Fx private-content"
                (server.succeed if name == "private" else server.fail)(private)
                direct = f"{prefix} --resolve private.example.test:9443:{address} https://private.example.test:9443/ | grep -Fx private-content"
                (server.succeed if name == "private" else server.fail)(direct)
                public = f"{prefix} --resolve public.example.test:443:{address} https://public.example.test/ | grep -Fx public-content"
                (server.fail if name == "private" else server.succeed)(public)
                # Public SNI with a private Host must not cross listeners.
                server.fail(f"{prefix} --resolve public.example.test:443:{address} -H 'Host: private.example.test' https://public.example.test/")
                for port, allowed in [(22, ["private", "relay"]), (7000, ["private"])]:
                    (server.succeed if name in allowed else server.fail)(f"{prefix} http://{address}:{port}/")
                family = "UDP6" if address.startswith("[") else "UDP4"
                command = f"printf test | ip netns exec {name} socat -T1 - {family}:{address}:60000 | grep -Fx test"
                (server.succeed if name in ["private", "relay"] else server.fail)(command)

    network_cases()
    # Simulate broad VPN accepts; raw guards must still win for IPv4 and IPv6.
    for tool in ["iptables", "ip6tables"]:
        server.succeed(f"{tool} -I INPUT -j ACCEPT")
    network_cases()
    server.succeed("systemctl stop firewall")
    network_cases()
    server.succeed("systemctl restart firewall")
    network_cases()
  '';
}
