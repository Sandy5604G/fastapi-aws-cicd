variable "region" {
  type        = string
  description = "AWS region to deploy into"
}

variable "project" {
  type    = string
  default = "fastapi-cicd"
}

variable "admin_cidr" {
  type        = string
  description = "Your public IP in CIDR form (x.x.x.x/32) allowed to reach Jenkins UI and SSH"
}

variable "github_hook_cidrs" {
  type        = list(string)
  default     = []
  description = "GitHub webhook IP ranges. Get with: curl -s https://api.github.com/meta | jq -r '.hooks[]' (IPv4 only)"
}

variable "jenkins_key_name" {
  type        = string
  default     = ""
  description = "Optional EC2 key pair name for SSH. Leave empty to use SSM Session Manager only."
}

variable "alert_email" {
  type        = string
  default     = ""
  description = "Email for CloudWatch alarm notifications (leave empty to skip)"
}

variable "certificate_arn" {
  type        = string
  default     = ""
  description = "Optional ACM certificate ARN. If set, HTTPS is enabled and HTTP redirects to HTTPS."
}

variable "create_jenkins" {
  type    = bool
  default = true
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}

variable "min_tasks" {
  type    = number
  default = 2
}

variable "max_tasks" {
  type    = number
  default = 6
}
