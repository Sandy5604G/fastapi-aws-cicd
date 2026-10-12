data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_instance" "jenkins" {
  count                       = var.create_jenkins ? 1 : 0
  ami                         = data.aws_ssm_parameter.ubuntu.value
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.jenkins[0].id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins[0].name
  key_name                    = var.jenkins_key_name == "" ? null : var.jenkins_key_name
  user_data                   = file("${path.module}/jenkins-userdata.sh")
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }
  tags = { Name = "${var.project}-jenkins" }
}

resource "aws_eip" "jenkins" {
  count    = var.create_jenkins ? 1 : 0
  instance = aws_instance.jenkins[0].id
  domain   = "vpc"
}
