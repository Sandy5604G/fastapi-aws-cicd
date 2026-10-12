# FastAPI → Jenkins → Docker → ECR → ECS Fargate (production-grade CI/CD)

```
GitHub push ─▶ Jenkins ─▶ Lint+Tests(80% cov) ─▶ Docker build ─▶ Trivy scan ─▶ ECR (git-SHA tag)
                                                                                    │
         Smoke test ◀─ ECS rolling deploy (circuit-breaker auto-rollback) ◀─ new task-def revision
                                  │
              Internet ─▶ ALB (public) ─▶ Fargate tasks (private subnets, autoscaled)
                                  └─▶ CloudWatch logs, alarms ─▶ SNS email
```

## What makes this stand out
| Area | What's done |
|---|---|
| Infrastructure | 100% Terraform: VPC, public/private subnets, NAT, ALB, ECR, ECS Fargate, IAM, alarms, Jenkins EC2 |
| Security | No AWS access keys anywhere (Jenkins uses an instance role), least-privilege IAM, tasks in private subnets, ECS SG only accepts traffic from the ALB, IMDSv2, encrypted disk, non-root + read-only container, Trivy scan gates the pipeline, ECR scan-on-push |
| Release safety | Immutable ECR tags (git SHA, never `latest`), new task-def revision per deploy, deployment circuit breaker with automatic rollback, post-deploy smoke test verifying the new SHA is live |
| Quality | Ruff lint, pytest with 80% coverage gate, JUnit reports in Jenkins |
| Operations | Autoscaling (CPU+memory), Container Insights, CloudWatch alarms (5xx, unhealthy hosts, CPU) to SNS email |
| Cost control | ECR lifecycle policy, log retention, single NAT, `terraform destroy` to tear down |

## Fill-in values (left blank on purpose)
| Where | Value |
|---|---|
| `infra/terraform.tfvars` | `region`, `admin_cidr` (your IP/32), optional `github_hook_cidrs`, `jenkins_key_name`, `alert_email`, `certificate_arn` |
| `Jenkinsfile` env block | `AWS_REGION`, `AWS_ACCOUNT_ID`, `ALB_URL` (all printed by `terraform output`) |
| GitHub | Webhook URL (printed as `github_webhook_url`) |

## Step 1: Provision AWS (from your Ubuntu machine)
Prereqs: Terraform ≥ 1.6, AWS CLI v2 configured with an admin-ish profile (`aws configure`), Docker.
```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # fill it in
terraform init

# 1a. create ECR first so we can push a bootstrap image
terraform apply -target=aws_ecr_repository.app

# 1b. push the bootstrap image (run from repo root)
cd ..
export AWS_REGION=<your-region> AWS_ACCOUNT_ID=<your-account-id>
./scripts/bootstrap.sh

# 1c. create everything else
cd infra && terraform apply
terraform output
```
Open `alb_url`. You should see the FastAPI JSON response.

## Step 2: Configure Jenkins
1. Open `jenkins_url` (wait ~3 min after apply). Unlock with:
   `aws ssm start-session` into the instance (or SSH if you set a key), then `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`
2. Install suggested plugins + **Timestamper**, **JUnit**, **GitHub**. (No AWS credentials plugin needed: the instance role does auth.)
3. New Item → **Pipeline** → *Pipeline script from SCM* → Git → your repo URL, branch `main`, script path `Jenkinsfile`. Tick **GitHub hook trigger for GITScm polling**.
4. Fill the blank values in the `Jenkinsfile` and push.

## Step 3: GitHub webhook
Repo → Settings → Webhooks → Add: Payload URL = `github_webhook_url`, content type `application/json`, "Just the push event".
Get GitHub's IPs for the security group: `curl -s https://api.github.com/meta | jq -r '.hooks[]'` (IPv4 only), add to `github_hook_cidrs`, re-apply.

## Step 4: Ship it
```bash
git add . && git commit -m "feat: first release" && git push origin main
```
Watch the stages run, then `curl <alb_url>/version` shows the deployed git SHA.

**Demo the rollback:** push a commit that makes `/health` return 500. The new tasks fail health checks, ECS rolls back automatically, the pipeline fails, and the old version keeps serving traffic.

## Local run
```bash
pip install -r requirements-dev.txt
ruff check app tests && pytest --cov=app
uvicorn app.main:app --reload
```

## Tear down (avoid charges: NAT Gateway + ALB bill hourly)
```bash
cd infra && terraform destroy
```

## Optional upgrades
- Terraform remote state (S3 + DynamoDB; stub in `versions.tf`)
- HTTPS: set `certificate_arn` (HTTP then auto-redirects)
- Blue/green with CodeDeploy, WAF on the ALB, Slack notifications in `post {}`
- EKS variant: replace `deploy.sh` with `kubectl set image` / `kubectl rollout status`
- Replace Jenkins with GitHub Actions + OIDC if you want zero servers to manage

## Notes
- Jenkins apt key URL in `infra/jenkins-userdata.sh`: confirm against jenkins.io's Linux install page.
- Pin versions: bump `requirements*.txt`, `TRIVY_VERSION`, and provider versions as needed.
