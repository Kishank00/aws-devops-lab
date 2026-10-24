data "aws_iam_policy_document" "app_deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:Kishank00@89375740/linux-diagnostic-tool@1414677387:ref:refs/heads/master"]
    }
  }
}

resource "aws_iam_role" "app_deploy" {
  name               = "github-actions-app-deploy"
  assume_role_policy = data.aws_iam_policy_document.app_deploy_trust.json
}

data "aws_iam_policy_document" "app_deploy" {
  # 1. The SSM document used to run shell commands
  statement {
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:ap-south-1::document/AWS-RunShellScript"]
  }

  # 2. ...but only on instances tagged as our app server
  statement {
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:ap-south-1:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Name"
      values   = ["devops-lab-dev-diagnostic"]
    }
  }

  # 3. Find the instance and read the command result (read-only)
  statement {
    actions = [
      "ec2:DescribeInstances",
      "ssm:GetCommandInvocation",
    ]
    resources = ["*"]
  }

  # 4. Log in to ECR (account-wide, so it can't be narrowed to one repo)
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # 5. Push images, only to this app's repo
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = ["arn:aws:ecr:ap-south-1:${data.aws_caller_identity.current.account_id}:repository/linux-diagnostic-tool"]
  }

  # 6. Record the live image tag after a successful deploy
  statement {
    actions   = ["ssm:GetParameter", "ssm:PutParameter"]
    resources = ["arn:aws:ssm:ap-south-1:${data.aws_caller_identity.current.account_id}:parameter/devops-lab-dev/sysdiag/image-tag"]
  }

  # 7. Roll out a release by replacing the ASG instances
  statement {
    actions = [
      "autoscaling:StartInstanceRefresh",
      "autoscaling:CancelInstanceRefresh",
    ]
    resources = ["arn:aws:autoscaling:ap-south-1:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/devops-lab-dev-asg"]
  }

  # 8. Watch the refresh progress (read-only, no resource-level support)
  statement {
    actions   = ["autoscaling:DescribeInstanceRefreshes"]
    resources = ["*"]
  }


}

resource "aws_iam_role_policy" "app_deploy" {
  name   = "app-deploy-ssm"
  role   = aws_iam_role.app_deploy.id
  policy = data.aws_iam_policy_document.app_deploy.json
}
