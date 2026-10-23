{ publicHost, adminHost }:
let
  # Server-wide surfaces: first-run setup, account administration, and central
  # login. Central login would send public visitors to the private admin host.
  # The space proxy uses plain HTTP for these targets, including SilverBullet
  # itself, which would reach the dashboard past this router.
  # NOTE: Rust `\d` is Unicode `\p{Nd}`; Go `\d` is ASCII only.
  privateOnly = builtins.concatStringsSep " || " [
    "PathPrefix(`/.setup`)"
    "PathPrefix(`/.dashboard`)"
    "PathPrefix(`/.auth/central`)"
    "PathRegexp(`^(/[^/]+)*/\\.proxy/(localhost|\\p{Nd}+\\.\\p{Nd}+\\.\\p{Nd}+\\.\\p{Nd}+|host\\.docker\\.internal)`)"
  ];
in
{
  http = {
    routers = {
      silverbullet = {
        rule = "Host(`${publicHost}`) && !(${privateOnly})";
        entryPoints = [ "websecure" ];
        service = "silverbullet";
        tls.certResolver = "le-dns";
      };
      silverbullet-login = {
        rule = "Host(`${publicHost}`) && Method(`POST`) && PathRegexp(`^(/[^/]+)*/\\.auth(/.*)?$`) && !(${privateOnly})";
        # NOTE: Default priority is rule length; the public rule is longer than 100.
        priority = 1000;
        entryPoints = [ "websecure" ];
        service = "silverbullet";
        middlewares = [ "silverbullet-login-ratelimit" ];
        tls.certResolver = "le-dns";
      };
      silverbullet-admin = {
        rule = "Host(`${adminHost}`)";
        entryPoints = [ "netbird" ];
        service = "silverbullet";
        tls.certResolver = "le-dns";
      };
    };
    services.silverbullet.loadBalancer.servers = [ { url = "http://silverbullet:3000"; } ];
    middlewares.silverbullet-login-ratelimit.rateLimit = {
      # NOTE: Built-in lockout is one shared counter, not per client.
      sourceCriterion.requestHeaderName = "Cf-Connecting-Ip";
      average = 10;
      period = "1m";
      burst = 10;
    };
  };
}
