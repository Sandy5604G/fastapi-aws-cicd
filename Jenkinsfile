pipeline {
  agent any

  options {
    timestamps()
    timeout(time: 30, unit: 'MINUTES')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  triggers {
    githubPush()
    pollSCM('H/5 * * * *')
  }

  environment {
    AWS_REGION      = 'ap-south-1'
    ECR_REPO        = 'fastapi-cicd'
    ECS_CLUSTER     = 'fastapi-cicd-cluster'
    ECS_SERVICE     = 'fastapi-cicd-service'
    ECS_TASK_FAMILY = 'fastapi-cicd-task'
    ALB_NAME        = 'fastapi-cicd-alb'
    TRIVY_VERSION   = '0.57.1'
    // Optional: set to your CloudWatch / Alarm SNS Topic ARN for failure notifications
    SNS_TOPIC_ARN   = ''
  }

  stages {

    stage('Validate & Prepare') {
      steps {
        script {
          env.GIT_SHA = sh(returnStdout: true, script: 'git rev-parse --short=8 HEAD').trim()

          // Dynamic AWS Account ID lookup with fallback
          try {
            env.AWS_ACCOUNT_ID = sh(returnStdout: true, script: 'aws sts get-caller-identity --query Account --output text').trim()
          } catch (Exception e) {
            echo "sts:GetCallerIdentity lookup failed or not on EC2 role; checking environment fallback..."
            if (!env.AWS_ACCOUNT_ID?.trim()) {
              error 'Unable to resolve AWS_ACCOUNT_ID automatically. Set AWS_ACCOUNT_ID in environment or verify IAM role.'
            }
          }

          env.REGISTRY  = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
          env.IMAGE_URI = "${env.REGISTRY}/${env.ECR_REPO}:${env.GIT_SHA}"
          env.IS_MAIN   = (env.GIT_BRANCH ==~ /(origin\/)?main/) ? 'true' : 'false'

          // Dynamic ALB DNS name lookup
          try {
            env.ALB_DNS = sh(returnStdout: true, script: """
              aws elbv2 describe-load-balancers --names ${env.ALB_NAME} --region ${env.AWS_REGION} \
                --query 'LoadBalancers[0].DNSName' --output text
            """).trim()
            env.ALB_URL = "http://${env.ALB_DNS}"
          } catch (Exception e) {
            echo "ALB lookup failed; checking fallback..."
            if (!env.ALB_URL?.trim()) {
              error "Could not resolve DNS for ALB ${env.ALB_NAME}. Ensure ALB exists and Jenkins role has elasticloadbalancing:DescribeLoadBalancers."
            }
          }

          echo "Target image: ${env.IMAGE_URI} | ALB URL: ${env.ALB_URL} | Branch is main: ${env.IS_MAIN}"
        }
      }
    }

    stage('Lint & Unit Tests') {
      steps {
        sh '''
          mkdir -p reports
          docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e PIP_CACHE_DIR=/tmp/pip \
            -v "$WORKSPACE":/w -w /w python:3.12-slim sh -c "
              pip install --user -q -r requirements-dev.txt &&
              python -m ruff format --check app tests &&
              python -m ruff check app tests &&
              python -m pytest --junitxml=reports/junit.xml \
                --cov=app --cov-report=xml:reports/coverage.xml --cov-fail-under=80"
        '''
      }
      post { always { junit allowEmptyResults: true, testResults: 'reports/junit.xml' } }
    }

    stage('Build Image') {
      steps {
        sh 'docker build --pull --build-arg APP_VERSION=${GIT_SHA} -t ${IMAGE_URI} .'
      }
    }

    stage('Security Scan (Trivy)') {
      steps {
        sh '''
          mkdir -p reports
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
            -v trivy-cache:/root/.cache aquasec/trivy:${TRIVY_VERSION} image \
            --db-repository public.ecr.aws/aquasecurity/trivy-db:2 \
            --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed --no-progress \
            --output /dev/stdout ${IMAGE_URI} | tee reports/trivy.txt
        '''
      }
    }

    stage('Push to ECR') {
      when { expression { env.IS_MAIN == 'true' } }
      steps {
        sh '''
          aws ecr get-login-password --region ${AWS_REGION} | \
            docker login --username AWS --password-stdin ${REGISTRY}

          if aws ecr describe-images --repository-name ${ECR_REPO} \
               --image-ids imageTag=${GIT_SHA} --region ${AWS_REGION} >/dev/null 2>&1; then
            echo "Image ${GIT_SHA} already in ECR, skipping push (idempotent)."
          else
            docker push ${IMAGE_URI}
          fi
        '''
      }
    }

    stage('Deploy to ECS') {
      when { expression { env.IS_MAIN == 'true' } }
      steps { sh './scripts/deploy.sh' }
    }

    stage('Smoke Test') {
      when { expression { env.IS_MAIN == 'true' } }
      steps {
        sh '''
          for i in $(seq 1 12); do
            RESPONSE=$(curl -fsS "${ALB_URL}/version" 2>/dev/null || true)
            if echo "$RESPONSE" | grep -q "${GIT_SHA}"; then
              echo "Smoke test passed: ${GIT_SHA} is live on ALB ($RESPONSE)"; exit 0
            fi
            echo "Waiting for version ${GIT_SHA}... ($i/12)"; sleep 10
          done
          echo "Smoke test failed: Version ${GIT_SHA} not verified on ALB within timeout"; exit 1
        '''
      }
    }
  }

  post {
    success { echo "Pipeline succeeded: Deployed ${env.IMAGE_URI}." }
    failure {
      script {
        echo 'Pipeline failed. If deployment reached ECS and tasks failed health checks, circuit breaker auto-rolled back.'
        if (env.SNS_TOPIC_ARN?.trim()) {
          sh """
            aws sns publish --topic-arn ${env.SNS_TOPIC_ARN} --region ${env.AWS_REGION} \
              --subject "Pipeline failed: ${env.JOB_NAME} #${env.BUILD_NUMBER}" \
              --message "SHA ${env.GIT_SHA} - ${env.BUILD_URL}" || true
          """
        }
      }
    }
    always {
      archiveArtifacts artifacts: 'reports/*', allowEmptyArchive: true
      sh '''
        docker image prune -af --filter "until=24h" || true
        docker builder prune -f --filter "until=24h" || true
      '''
    }
  }
}
