mock_provider "aws" {
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::148676508643:oidc-provider/ampcode.com/api/workload-identity"
    }
  }
}

variables {
  backup_bucket       = "openbao-vpn-backup-148676508643"
  openbao_kms_key_arn = "arn:aws:kms:ca-central-1:148676508643:key/12345678-1234-1234-1234-123456789012"
}

run "only_the_project_and_sso_administrator_are_trusted" {
  command = plan

  assert {
    condition = (
      aws_iam_openid_connect_provider.amp.url == "https://ampcode.com/api/workload-identity" &&
      aws_iam_openid_connect_provider.amp.client_id_list == toset(["urn:amp:aws:tofu-plan:148676508643"])
    )
    error_message = "The Amp issuer must accept only the dedicated plan audience."
  }

  assert {
    condition = jsondecode(aws_iam_role.plan.assume_role_policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Principal = {
            Federated = "arn:aws:iam::148676508643:oidc-provider/ampcode.com/api/workload-identity"
          }
          Action = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = {
              "ampcode.com/api/workload-identity:aud" = "urn:amp:aws:tofu-plan:148676508643"
              "ampcode.com/api/workload-identity:sub" = "user:user_01K8F9XNBP340JTA7EXNMV9QW3:project:d652cd02-f7c9-4fd9-ad79-3eb9c935736e"
            }
          }
        },
        {
          Effect = "Allow"
          Principal = {
            AWS = "arn:aws:iam::148676508643:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_8e45cdd61884f702"
          }
          Action = "sts:AssumeRole"
        },
      ]
    }
    error_message = "Trust must require the exact project subject and audience, or the exact SSO administrator role."
  }

  assert {
    condition     = aws_iam_role.plan.name == "tofu-plan" && aws_iam_role.plan.max_session_duration == 3600
    error_message = "The plan role must have a stable name and a one-hour session limit."
  }
}

run "state_and_backup_content_are_protected" {
  command = plan

  assert {
    condition = [for statement in jsondecode(aws_iam_role_policy.refresh.policy).Statement : statement if statement.Sid == "MainStateContent"] == [
      {
        Sid      = "MainStateContent"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::terraform-state-denys-me/state"]
      },
    ]
    error_message = "Object reads must allow only the main state key, never bao-config/state or state versions."
  }

  assert {
    condition = [for statement in jsondecode(aws_iam_role_policy.refresh.policy).Statement : statement if statement.Sid == "DenyBackupObjects"] == [
      {
        Sid      = "DenyBackupObjects"
        Effect   = "Deny"
        Action   = ["s3:*"]
        Resource = ["arn:aws:s3:::openbao-vpn-backup-148676508643/*"]
      },
    ]
    error_message = "Bao objects must deny every action, including reads, versions, restore and multipart operations."
  }

  assert {
    condition = [for statement in jsondecode(aws_iam_role_policy.refresh.policy).Statement : statement if statement.Sid == "DenyStateObjectMutations"] == [
      {
        Sid       = "DenyStateObjectMutations"
        Effect    = "Deny"
        NotAction = ["s3:GetObject"]
        Resource  = ["arn:aws:s3:::terraform-state-denys-me/*"]
      },
    ]
    error_message = "All state object actions except current-version GetObject must be explicitly denied, including lockfile writes."
  }

  assert {
    condition = [for statement in jsondecode(aws_iam_role_policy.refresh.policy).Statement : statement if statement.Sid == "DenyOtherObjectReads"] == [
      {
        Sid         = "DenyOtherObjectReads"
        Effect      = "Deny"
        Action      = ["s3:GetObject*"]
        NotResource = ["arn:aws:s3:::terraform-state-denys-me/state"]
      },
    ]
    error_message = "Other state keys, including Bao configuration state, must remain unreadable even with another allow policy."
  }
}

run "bucket_metadata_exception_never_allows_writes" {
  command = plan

  assert {
    condition = [for statement in jsondecode(aws_iam_role_policy.refresh.policy).Statement : statement if statement.Sid == "BucketConfiguration"] == [
      {
        Sid    = "BucketConfiguration"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketPolicy",
          "s3:GetBucketAcl",
          "s3:GetBucketCORS",
          "s3:GetBucketWebsite",
          "s3:GetBucketVersioning",
          "s3:GetAccelerateConfiguration",
          "s3:GetBucketRequestPayment",
          "s3:GetBucketLogging",
          "s3:GetLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetBucketTagging",
        ]
        Resource = ["arn:aws:s3:::terraform-state-denys-me", "arn:aws:s3:::openbao-vpn-backup-148676508643"]
      },
    ]
    error_message = "The reviewed exception permits only bucket configuration and unprefixed key listing on the two managed buckets."
  }

  assert {
    condition = alltrue([for sid, bucket in {
      DenyStateBucketMutations  = "arn:aws:s3:::terraform-state-denys-me"
      DenyBackupBucketMutations = "arn:aws:s3:::openbao-vpn-backup-148676508643"
      } : [for statement in jsondecode(aws_iam_role_policy.refresh.policy).Statement : statement if statement.Sid == sid] == [
      {
        Sid    = sid
        Effect = "Deny"
        NotAction = concat([
          "s3:ListBucket",
          "s3:GetBucketPolicy",
          "s3:GetBucketAcl",
          "s3:GetBucketCORS",
          "s3:GetBucketWebsite",
          "s3:GetBucketVersioning",
          "s3:GetAccelerateConfiguration",
          "s3:GetBucketRequestPayment",
          "s3:GetBucketLogging",
          "s3:GetLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetBucketTagging",
        ], sid == "DenyBackupBucketMutations" ? ["s3:GetBucketPublicAccessBlock"] : [])
        Resource = [bucket]
      },
    ]])
    error_message = "Both buckets must explicitly deny every non-allowlisted bucket operation, including policy, encryption, lifecycle and versioning writes."
  }
}

run "refresh_allowlist_is_resource_scoped_and_contains_no_secret_reads" {
  command = plan

  assert {
    condition = { for statement in jsondecode(aws_iam_role_policy.refresh.policy).Statement : statement.Sid => statement if statement.Effect == "Allow" && !contains(["MainStateContent", "BucketConfiguration"], statement.Sid) } == {
      BackupPublicAccessConfiguration = {
        Sid      = "BackupPublicAccessConfiguration"
        Effect   = "Allow"
        Action   = ["s3:GetBucketPublicAccessBlock"]
        Resource = ["arn:aws:s3:::openbao-vpn-backup-148676508643"]
      }
      StateLockConfiguration = {
        Sid      = "StateLockConfiguration"
        Effect   = "Allow"
        Action   = ["dynamodb:DescribeTable", "dynamodb:DescribeContinuousBackups", "dynamodb:DescribeTimeToLive", "dynamodb:ListTagsOfResource"]
        Resource = ["arn:aws:dynamodb:us-east-1:148676508643:table/terraform-state-lock-denys-me"]
      }
      UnsealKeyConfiguration = {
        Sid      = "UnsealKeyConfiguration"
        Effect   = "Allow"
        Action   = ["kms:DescribeKey", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListResourceTags"]
        Resource = ["arn:aws:kms:ca-central-1:148676508643:key/12345678-1234-1234-1234-123456789012"]
      }
      UnsealAliasDiscovery = {
        Sid      = "UnsealAliasDiscovery"
        Effect   = "Allow"
        Action   = ["kms:ListAliases"]
        Resource = ["*"]
        Condition = {
          StringEquals = { "aws:RequestedRegion" = "ca-central-1" }
        }
      }
      BaoUserConfiguration = {
        Sid      = "BaoUserConfiguration"
        Effect   = "Allow"
        Action   = ["iam:GetUser", "iam:GetUserPolicy"]
        Resource = ["arn:aws:iam::148676508643:user/openbao-vpn-runtime", "arn:aws:iam::148676508643:user/openbao-vpn-backup"]
      }
      AmpIssuerConfiguration = {
        Sid      = "AmpIssuerConfiguration"
        Effect   = "Allow"
        Action   = ["iam:GetOpenIDConnectProvider"]
        Resource = ["arn:aws:iam::148676508643:oidc-provider/ampcode.com/api/workload-identity"]
      }
      PlanRoleConfiguration = {
        Sid      = "PlanRoleConfiguration"
        Effect   = "Allow"
        Action   = ["iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies"]
        Resource = ["arn:aws:iam::148676508643:role/tofu-plan"]
      }
    }
    error_message = "Refresh must use only the reviewed S3, DynamoDB, KMS and IAM metadata actions on managed resources; no managed ReadOnlyAccess, cryptographic operations or data reads."
  }

  assert {
    condition     = aws_iam_role_policy.refresh.role == "tofu-plan" && length(jsondecode(aws_iam_role_policy.refresh.policy).Statement) == 14
    error_message = "The plan role must receive exactly the reviewed inline policy statements."
  }
}
