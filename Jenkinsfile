pipeline {
  agent any

  options {
    timestamps()
    timeout(time: 30, unit: 'MINUTES')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  triggers { githubPush() }

  environment {
    // ====== FILL THESE IN (values come from `terraform output`) ======
    AWS_REGION      = 'ap-south-1'
    AWS_ACCOUNT_ID  = '800168266526'
    ALB_URL         = 'http://fastapi-cicd-alb-1317333918.ap-south-1.elb.amazonaws.com'
    // ====== Defaults match infra/variables.tf (project = fastapi-cicd) ======
    ECR_REPO        = 'fastapi-cicd'
    ECS_CLUSTER     = 'fastapi-cicd-cluster'
    ECS_SERVICE     = 'fastapi-cicd-service'
    ECS_TASK_FAMILY = 'fastapi-cicd-task'
    DESIRED_COUNT   = '2'
    TRIVY_VERSION   = '0.57.1'
  }

  stages {

    stage('Validate & Prepare') {
      steps {
        script {
          if (!env.AWS_REGION?.trim() || !env.AWS_ACCOUNT_ID?.trim() || !env.ALB_URL?.trim()) {
            error 'Fill AWS_REGION, AWS_ACCOUNT_ID and ALB_URL in the Jenkinsfile environment block.'
          }
          env.GIT_SHA   = sh(returnStdout: true, script: 'git rev-parse --short=8 HEAD').trim()
          env.REGISTRY  = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
          env.IMAGE_URI = "${env.REGISTRY}/${ECR_REPO}:${env.GIT_SHA}"
          env.IS_MAIN   = (env.GIT_BRANCH ==~ /(origin\/)?main/) ? 'true' : 'false'
          echo "Image: ${env.IMAGE_URI} | deploy branch: ${env.IS_MAIN}"
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
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
            -v trivy-cache:/root/.cache aquasec/trivy:${TRIVY_VERSION} image \
            --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed --no-progress ${IMAGE_URI}
        '''
      }
    }

    stage('Push to ECR') {
      when { expression { env.IS_MAIN == 'true' } }
      steps {
        sh '''
          aws ecr get-login-password --region ${AWS_REGION} | \
            docker login --username AWS --password-stdin ${REGISTRY}
          docker push ${IMAGE_URI}
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
          for i in $(seq 1 10); do
            if curl -fsS "${ALB_URL}/version" | grep -q "${GIT_SHA}"; then
              echo "Smoke test passed: ${GIT_SHA} is live"; exit 0
            fi
            echo "Waiting for new version... ($i/10)"; sleep 10
          done
          echo "Smoke test failed"; exit 1
        '''
      }
    }
  }

  post {
    success { echo "Deployed ${env.IMAGE_URI}" }
    failure { echo 'Failed. If it failed during deploy, the ECS circuit breaker has rolled back automatically.' }
    always  { sh 'docker image prune -f || true' }
  }
}
