data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.project}-task-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Role the application itself runs as (add app permissions here later)
resource "aws_iam_role" "task" {
  name               = "${var.project}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# ---------- Jenkins: instance role instead of long-lived access keys ----------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins" {
  count              = var.create_jenkins ? 1 : 0
  name               = "${var.project}-jenkins"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  count      = var.create_jenkins ? 1 : 0
  role       = aws_iam_role.jenkins[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "jenkins" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages"
    ]
    resources = [aws_ecr_repository.app.arn]
  }
  statement {
    sid       = "EcsRead"
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition", "ecs:DescribeServices", "ecs:DescribeTasks", "ecs:ListTasks"]
    resources = ["*"]
  }
  statement {
    sid       = "EcsDeploy"
    actions   = ["ecs:UpdateService"]
    resources = [aws_ecs_service.app.id]
  }
  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.task_execution.arn, aws_iam_role.task.arn]
  }
  statement {
    sid       = "DescribeALB"
    actions   = ["elasticloadbalancing:DescribeLoadBalancers"]
    resources = ["*"]
  }
  statement {
    sid       = "SnsPublishAlarms"
    actions   = ["sns:Publish"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "jenkins" {
  count  = var.create_jenkins ? 1 : 0
  name   = "cicd-deploy"
  role   = aws_iam_role.jenkins[0].id
  policy = data.aws_iam_policy_document.jenkins.json
}

resource "aws_iam_instance_profile" "jenkins" {
  count = var.create_jenkins ? 1 : 0
  name  = "${var.project}-jenkins"
  role  = aws_iam_role.jenkins[0].name
}
