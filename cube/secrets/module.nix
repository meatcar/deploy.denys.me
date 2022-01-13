{ ... }:
{
  age.secrets = {
    ssmtpPass.file = ./ssmtp-pass.age;
    transmissionUser.file = ./transmission-user.age;
    transmissionPass.file = ./transmission-pass.age;
    hashedPassword.file = ./hashed-password.age;
    cloudflareKey.file = ./cloudflare-key.age;
  };
}
