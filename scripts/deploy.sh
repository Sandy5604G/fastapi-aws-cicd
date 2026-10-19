#!/usr/bin/env bash
# Registers a new task definition revision with the new image and rolls it out.
# ECS deployment circuit breaker (enabled in Terraform) auto-rolls back on failure.
set -euo pipefail

: "${AWS_REGION:?}" "${ECS_CLUSTER:?}" "${ECS_SERVICE:?}" "${ECS_TASK_FAMILY:?}" "${IMAGE_URI:?}"

echo ">> Fetching current task definition: ${ECS_TASK_FAMILY}"
aws ecs describe-task-definition --region "$AWS_REGION" \
  --task-definition "$ECS_TASK_FAMILY" --query taskDefinition > td.json

jq --arg IMG "$IMAGE_URI" '
  del(.taskDefinitionArn,.revision,.status,.requiresAttributes,.compatibilities,.registeredAt,.registeredBy)
  | .containerDefinitions[0].image = $IMG' td.json > new-td.json

echo ">> Registering new revision with image ${IMAGE_URI}"
NEW_ARN=$(aws ecs register-task-definition --region "$AWS_REGION" \
  --cli-input-json file://new-td.json --query 'taskDefinition.taskDefinitionArn' --output text)
echo "   -> ${NEW_ARN}"

echo ">> Updating service ${ECS_SERVICE} with new task definition"
aws ecs update-service --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" --task-definition "$NEW_ARN" >/dev/null

echo ">> Waiting for service to become stable..."
aws ecs wait services-stable --region "$AWS_REGION" --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"

ROLLOUT=$(aws ecs describe-services --region "$AWS_REGION" --cluster "$ECS_CLUSTER" \
  --services "$ECS_SERVICE" --query 'services[0].deployments[?status==`PRIMARY`].rolloutState' --output text)
echo ">> Rollout state: ${ROLLOUT}"
[ "$ROLLOUT" = "COMPLETED" ] || { echo "Deployment did not complete (rolled back?)"; exit 1; }
