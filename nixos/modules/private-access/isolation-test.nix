{ pkgs, sambaSettings }:
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
          trustedLANInterfaces = [ "lan0" ];
        };
        networking.dhcpcd.denyInterfaces = [
          "wt0"
          "tailscale0"
          "pub0"
          "lan0"
        ];
        networking.firewall.interfaces = {
          wt0.allowedTCPPorts = [ 445 ];
          lan0 = {
            allowedTCPPorts = [
              445
              5357
            ];
            allowedUDPPorts = [ 3702 ];
          };
        };
        services.nginx.virtualHosts = {
          "plex.example.test" = tls // {
            locations."/".return = "200 plex-public";
          };
          "ombi.example.test" = tls // {
            locations."/".return = "200 ombi-public";
          };
          "private.example.test" = tls // {
            locations."/".return = "200 private-content";
          };
        };
        services.samba = {
          enable = true;
          nmbd.enable = false;
          settings = sambaSettings // {
            global = sambaSettings.global // {
              interfaces = "lo wt0 lan0";
            };
            data = sambaSettings.data // {
              path = "/srv/share";
            };
          };
        };
        users.groups.storage = { };
        users.users.alice = {
          isNormalUser = true;
          extraGroups = [ "storage" ];
        };
        environment.systemPackages = with pkgs; [
          curl
          iproute2
          iptables
          samba
          socat
        ];
        systemd.services =
          lib.genAttrs [ "probe-22" "probe-7000" "probe-5357" ] (name: {
            wantedBy = [ "multi-user.target" ];
            serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${lib.removePrefix "probe-" name} --bind ::";
          })
          // lib.genAttrs [ "udp-3702" "udp-60000" ] (name: {
            wantedBy = [ "multi-user.target" ];
            serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${./udp-echo.py} ${lib.removePrefix "udp-" name}";
          });
      };
    proxy =
      { nodes, ... }:
      {
        imports = [
          ../nginx.nix
          ../nginx-sni-proxy.nix
        ];
        mine.nginx-sni-proxy = {
          enable = true;
          proxies = {
            "plex.example.test".host = nodes.server.networking.primaryIPAddress;
            "ombi.example.test".host = nodes.server.networking.primaryIPAddress;
          };
        };
        services.nginx.virtualHosts."website.example.test" = tls // {
          locations."/".return = "200 website-public";
        };
        environment.systemPackages = [ pkgs.curl ];
      };
  };
  testScript = ''
    start_all()
    server.wait_for_unit("nginx.service")
    proxy.wait_for_unit("nginx.service")
    for host, body in [("plex", "plex-public"), ("ombi", "ombi-public"), ("website", "website-public")]:
        proxy.succeed(f"curl -kfsS --resolve {host}.example.test:443:127.0.0.1 https://{host}.example.test/ | grep -Fx {body}")
    # Public SNI with a private Host must not cross listeners. The inverse fails TLS.
    for host in ["plex", "ombi", "website"]:
        proxy.fail(f"curl -kfsS --resolve {host}.example.test:443:127.0.0.1 -H 'Host: private.example.test' https://{host}.example.test/")
    for host in ["private", "unknown", "sub.plex"]:
        proxy.fail(f"curl -kfsS --resolve {host}.example.test:443:127.0.0.1 -H 'Host: plex.example.test' https://{host}.example.test/")

    for subnet, (name, interface) in enumerate([("private", "wt0"), ("public", "pub0"), ("relay", "tailscale0"), ("lan", "lan0")], 1):
        server.succeed(f"ip netns add {name}")
        server.succeed(f"ip link add {interface} type veth peer name peer netns {name}")
        server.succeed(f"ip addr add 192.0.{subnet}.1/24 dev {interface}; ip link set {interface} up")
        server.succeed(f"ip -6 addr add fd00:{subnet}::1/64 dev {interface} nodad")
        server.succeed(f"ip -n {name} addr add 192.0.{subnet}.2/24 dev peer; ip -n {name} link set peer up; ip -n {name} link set lo up")
        server.succeed(f"ip -n {name} -6 addr add fd00:{subnet}::2/64 dev peer nodad")
    server.succeed("mkdir -p /srv/share; chmod 755 /srv/share; printf 'fixture-pass\\nfixture-pass\\n' | smbpasswd -a -s alice; systemctl restart samba-smbd")
    for port in [22, 7000, 5357]:
        server.wait_for_unit(f"probe-{port}.service")
    for port in [3702, 60000]:
        server.wait_for_unit(f"udp-{port}.service")

    def network_cases():
        for subnet, name in enumerate(["private", "public", "relay", "lan"], 1):
            for address in [f"192.0.{subnet}.1", f"[fd00:{subnet}::1]"]:
                prefix = f"ip netns exec {name} curl --noproxy '*' -gkfsS --max-time 2"
                private = f"{prefix} --resolve private.example.test:443:{address} https://private.example.test/ | grep -Fx private-content"
                (server.succeed if name == "private" else server.fail)(private)
                direct = f"{prefix} --resolve private.example.test:9443:{address} https://private.example.test:9443/ | grep -Fx private-content"
                (server.succeed if name == "private" else server.fail)(direct)
                for port, allowed in [(22, ["private", "relay"]), (7000, ["private"]), (5357, ["lan"])]:
                    (server.succeed if name in allowed else server.fail)(f"{prefix} http://{address}:{port}/")
                # Tailscale transport alone cannot grant private HTTP access.
                if name == "relay":
                    server.fail(f"{prefix} --resolve plex.example.test:443:{address} -H 'Host: private.example.test' https://plex.example.test/")
                for port, allowed in [(60000, ["private", "relay"]), (3702, ["lan"])]:
                    family = "UDP6" if address.startswith("[") else "UDP4"
                    command = f"printf test | ip netns exec {name} socat -T1 - {family}:{address}:{port} | grep -Fx test"
                    (server.succeed if name in allowed else server.fail)(command)
                ip = address.strip("[]")
                smb = f"ip netns exec {name} smbclient //server/data -I {ip} -U alice%fixture-pass -c ls --timeout=2"
                (server.succeed if name in ["private", "lan"] else server.fail)(smb)
                server.fail(f"ip netns exec {name} smbclient //server/data -I {ip} -N -c ls --timeout=2")

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
