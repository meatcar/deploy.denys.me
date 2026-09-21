data "aws_iam_policy_document" "aws_auth" {
  statement {
    actions   = ["iam:GetRole"]
    resources = ["arn:aws:iam::148676508643:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_8e45cdd61884f702"]
  }
}

resource "aws_iam_user_policy" "aws_auth" {
  name   = "openbao-resolve-sso-admin"
  user   = aws_iam_user.openbao.name
  policy = data.aws_iam_policy_document.aws_auth.json
}
