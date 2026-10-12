output "alb_url" {
  value = "${local.https ? "https" : "http"}://${aws_lb.app.dns_name}"
}
output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
output "aws_account_id"     { value = data.aws_caller_identity.me.account_id }
output "ecs_cluster"        { value = aws_ecs_cluster.main.name }
output "ecs_service"        { value = aws_ecs_service.app.name }
output "jenkins_url" {
  value = var.create_jenkins ? "http://${aws_eip.jenkins[0].public_ip}:8080" : null
}
output "github_webhook_url" {
  value = var.create_jenkins ? "http://${aws_eip.jenkins[0].public_ip}:8080/github-webhook/" : null
}
