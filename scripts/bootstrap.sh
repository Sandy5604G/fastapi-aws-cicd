#!/usr/bin/env bash
# One-time: push a first image (tag "bootstrap") so the ECS service can start.
set -euo pipefail
: "${AWS_REGION:?}" "${AWS_ACCOUNT_ID:?}"
ECR_REPO="${ECR_REPO:-fastapi-cicd}"
REG="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REG"
docker build -t "${REG}/${ECR_REPO}:bootstrap" --build-arg APP_VERSION=bootstrap .
docker push "${REG}/${ECR_REPO}:bootstrap"
