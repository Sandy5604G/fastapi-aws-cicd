# FastAPI → Jenkins → Docker → ECR → ECS Fargate (Production-Grade CI/CD)

```
GitHub push ─▶ Jenkins ─▶ Lint+Tests(80% cov) ─▶ Docker build ─▶ Trivy scan ─▶ ECR (git-SHA tag)
                                                                                    │
         Smoke test ◀─ ECS rolling deploy (circuit-breaker auto-rollback) ◀─ new task-def revision
                                  │
              Internet ─▶ ALB (public) ─▶ Fargate tasks (private subnets, autoscaled)
                                  └─▶ CloudWatch logs, alarms ─▶ SNS alert
```

## Highlights & Engineering Standards
| Area | Architecture & Implementation |
|---|---|
| **Infrastructure** | 100% codified via Terraform: Custom VPC, public/private subnets across 2 AZs, NAT Gateway, ALB, ECR, ECS Fargate, IAM instance profiles, CloudWatch alarms, and Jenkins EC2 |
| **Security** | Zero hardcoded access keys (Jenkins assumes EC2 IAM instance role with least privilege), ECS tasks run in private subnets, security group restricts ingress strictly to ALB traffic, IMDSv2 enforced, encrypted EBS volumes, non-root user (`USER 10001`), read-only container root filesystem, Aqua Security Trivy scan gates builds on 0 HIGH/CRITICAL CVEs |
| **Release Safety** | Immutable ECR tags (git SHA, never `latest`), idempotent image push check (`ecr:DescribeImages`), new Task Definition revision per deploy, ECS deployment circuit breaker with automatic rollback, post-deploy smoke test verifying git-SHA live on ALB |
| **Pipeline Quality** | Dockerized runner, Ruff format + lint checks, Pytest with strict 80% coverage gate (100% achieved), JUnit & XML test reports archived |
| **Operations & Resilience** | Dual-metric autoscaling (CPU 60%, Memory 70%), CloudWatch Container Insights, ALB 5xx / unhealthy host metric alarms, automated Docker builder & image 24h prune |
| **Cost Control** | Single NAT Gateway for private subnets, aggressive ECR lifecycle policies (retains 10 untagged / 30 tagged), 30-day CloudWatch log retention, clean single-command `terraform destroy` |

---

## Configuration Variables
| Where | Parameters |
|---|---|
| `infra/terraform.tfvars` | `region`, `admin_cidr` (your IP/32), optional `github_hook_cidrs`, `jenkins_key_name`, `alert_email`, `certificate_arn` |
| `Jenkinsfile` | Automatically discovers `AWS_ACCOUNT_ID` and `ALB_URL` at runtime via instance IAM role. Defaults match `infra/variables.tf` (`project = fastapi-cicd`). |
| GitHub | Webhook URL (`http://<jenkins-ip>:8080/github-webhook/`) |

---

## Local Development & Testing

### Option A: Using Docker Compose (Recommended)
```bash
# Build and run containerized app locally on port 8000
docker compose up --build

# Verify health and endpoints
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/version
```

### Option B: Local Python Virtual Environment
```bash
pip install -r requirements-dev.txt
python -m ruff format --check app tests
python -m ruff check app tests
python -m pytest --cov=app --cov-report=term-missing --cov-fail-under=80
uvicorn app.main:app --reload
```

---

## Deployment Guide

### Step 1: Provision Infrastructure via Terraform
Prerequisites: Terraform ≥ 1.6, AWS CLI v2 configured with an active admin profile, Docker.
```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # configure admin_cidr and region
terraform init

# 1a. Create ECR repository first to host the bootstrap image
terraform apply -target=aws_ecr_repository.app

# 1b. Build and push bootstrap image (run from repository root)
cd ..
export AWS_REGION=ap-south-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
./scripts/bootstrap.sh

# 1c. Provision complete infrastructure stack (ALB, ECS cluster, service, Jenkins EC2)
cd infra
terraform apply
terraform output
```

### Step 2: Configure Jenkins
1. Open the Jenkins web console: `http://<jenkins_public_ip>:8080`.
2. Retrieve initial admin password via AWS SSM Session Manager:
   ```bash
   aws ssm start-session --target <jenkins-instance-id>
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```
3. Install recommended plugins + **Timestamper**, **JUnit**, **GitHub**. (No AWS credentials plugin required; Jenkins authenticates seamlessly via its attached IAM instance role).
4. Create New Item → **Pipeline** → *Pipeline script from SCM* → Git → specify repository URL, branch `main`, script path `Jenkinsfile`. Check **GitHub hook trigger for GITScm polling**.

### Step 3: Configure GitHub Webhook
1. Go to repository **Settings** → **Webhooks** → **Add webhook**.
2. Payload URL: `http://<jenkins_public_ip>:8080/github-webhook/`
3. Content type: `application/json`
4. Trigger on: "Just the push event".

### Step 4: Continuous Delivery
```bash
git add .
git commit -m "feat: production improvements"
git push origin main
```
The pipeline automatically runs formatting checks, linting, tests, container build, Trivy vulnerability gating, idempotent ECR push, rolling zero-downtime deployment, and smoke testing against the live ALB endpoint.

---

## Rollback Demo (Fault Tolerance Verification)
To demonstrate the ECS deployment circuit breaker in a viva or demo:
1. Introduce a failure (e.g. modify `/health` in `app/main.py` to return HTTP 500).
2. Commit and push to `main`.
3. Jenkins builds the image and triggers ECS rollout.
4. Fargate health checks fail, the deployment circuit breaker detects target degradation, stops rollout, and automatically restores previous stable tasks.
5. The pipeline fails gracefully, and live users experience zero downtime.

---

## Clean Teardown (Avoid Unnecessary AWS Charges)
ALB and NAT Gateway bill hourly. When done with your presentation or viva, tear down all AWS resources with a single command:
```bash
cd infra
terraform destroy -auto-approve
```
