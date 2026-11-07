// Pipeline de CI/CD de la app (Task/Incident Tracker).
// checkout -> tests -> build+tag -> push ECR -> deploy (SSM) -> smoke test
// -> marcar estable (solo si el smoke test paso) -> rollback automatico
// (solo si algo de lo anterior falla).
//
// Nota de diseno: este pipeline NO incluye "terraform apply" a proposito.
// Ver docs/ARCHITECTURE.md seccion 3 ("por que Terraform NO esta en este
// pipeline"): la infraestructura se gestiona aparte, con permisos aparte.
//
// Credenciales AWS: ninguna configurada en Jenkins. jenkins-server corre
// con el rol de instancia student-jenkins-ec2-role (SSM + push a ECR);
// cualquier `aws`/`docker login` de este pipeline usa ese rol automatica-
// mente via el servicio de metadatos de EC2 (verificado con
// `docker exec jenkins aws sts get-caller-identity`, sin perfil ni claves).
//
// Estrategia de rollback: cada build etiqueta la imagen con el commit-sha
// (trazabilidad) y, SOLO si el smoke test pasa, mueve ademas el tag
// ":stable" a esa imagen. El rollback nunca inspecciona el servidor remoto:
// simplemente vuelve a desplegar lo que ":stable" tenga en ese momento, que
// por definicion es la ultima version que sí funciono.

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        AWS_REGION   = 'eu-west-1'
        PROJECT_NAME = 'task-tracker'
        APP_REPO     = 'task-tracker-app'
        APP_PORT     = '5000'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_SHA    = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.ACCOUNT_ID = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
                    env.ECR_REGISTRY = "${env.ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                    env.IMAGE = "${env.ECR_REGISTRY}/${env.APP_REPO}"

                    env.APP_INSTANCE_ID = sh(
                        script: "aws ec2 describe-instances --filters \"Name=tag:Name,Values=${env.PROJECT_NAME}-app-server\" \"Name=instance-state-name,Values=running\" --query \"Reservations[0].Instances[0].InstanceId\" --output text",
                        returnStdout: true
                    ).trim()

                    env.ALB_DNS = sh(
                        script: "aws elbv2 describe-load-balancers --names ${env.PROJECT_NAME}-alb --query 'LoadBalancers[0].DNSName' --output text",
                        returnStdout: true
                    ).trim()
                }
                echo "Commit ${env.GIT_SHA} -> ${env.IMAGE}:${env.GIT_SHA} | app-server=${env.APP_INSTANCE_ID} | ALB=${env.ALB_DNS}"
            }
        }

        stage('Tests') {
            steps {
                dir('app') {
                    sh '''
                        python3 -m venv .venv
                        . .venv/bin/activate
                        pip install --no-cache-dir -q -r requirements.txt pytest pytest-cov
                        pytest --cov=. --cov-report=term-missing
                    '''
                }
            }
        }

        stage('Build & tag imagen Docker') {
            steps {
                dir('app') {
                    sh "docker build --build-arg GIT_SHA=${env.GIT_SHA} -t ${env.IMAGE}:${env.GIT_SHA} ."
                }
            }
        }

        stage('Push a ECR') {
            steps {
                sh """
                    aws ecr get-login-password --region ${env.AWS_REGION} \
                      | docker login --username AWS --password-stdin ${env.ECR_REGISTRY}
                    docker push ${env.IMAGE}:${env.GIT_SHA}
                """
            }
        }

        stage('Deploy a app-server (SSM)') {
            steps {
                script {
                    deployTag(env.GIT_SHA)
                }
            }
        }

        stage('Smoke test') {
            steps {
                script {
                    smokeTest(env.GIT_SHA)
                }
            }
        }

        stage('Marcar como estable') {
            steps {
                // Solo se llega aqui si el smoke test (stage anterior) ha
                // pasado. A partir de ahora, ":stable" es esta version.
                sh """
                    docker tag ${env.IMAGE}:${env.GIT_SHA} ${env.IMAGE}:stable
                    docker push ${env.IMAGE}:stable
                """
            }
        }
    }

    post {
        failure {
            script {
                def hayVersionEstable = sh(
                    script: "aws ecr describe-images --repository-name ${env.APP_REPO} --image-ids imageTag=stable >/dev/null 2>&1",
                    returnStatus: true
                ) == 0

                if (hayVersionEstable) {
                    echo "Algo fallo. Rollback automatico al tag :stable (ultima version que si funciono)."
                    deployTag('stable')
                    // En el rollback solo comprobamos que el servicio vuelve a
                    // responder sano; no hace falta verificar el SHA exacto,
                    // porque ":stable" es por definicion la ultima version valida.
                    sh """
                        for i in \$(seq 1 20); do
                          HEALTH=\$(curl -s -o /dev/null -w '%{http_code}' "http://${env.ALB_DNS}/health" || echo 000)
                          if [ "\$HEALTH" = "200" ]; then echo "Rollback OK, servicio sano de nuevo."; exit 0; fi
                          sleep 10
                        done
                        echo "Rollback tambien fallo en comprobar /health. Requiere intervencion manual."
                        exit 1
                    """
                } else {
                    echo "Algo fallo y no hay ninguna version :stable previa (primer despliegue). No hay a que volver."
                }
            }
        }
    }
}

// Despliega un tag concreto en app-server via SSM Run Command (sin SSH).
// Se usa tanto para el despliegue normal como para el rollback: ambos son
// "desplegar un tag", solo cambia cual.
void deployTag(String tag) {
    writeFile file: 'ssm-deploy.json', text: """{
  "commands": [
    "aws ecr get-login-password --region ${env.AWS_REGION} | docker login --username AWS --password-stdin ${env.ECR_REGISTRY}",
    "docker pull ${env.IMAGE}:${tag}",
    "docker stop app || true",
    "docker rm app || true",
    "docker run -d --name app --restart unless-stopped -p ${env.APP_PORT}:${env.APP_PORT} --log-driver awslogs --log-opt awslogs-region=${env.AWS_REGION} --log-opt awslogs-group=/${env.PROJECT_NAME}/app-server --log-opt awslogs-stream=app ${env.IMAGE}:${tag}"
  ]
}"""
    sh """
        CMD_ID=\$(aws ssm send-command --instance-ids "${env.APP_INSTANCE_ID}" --document-name "AWS-RunShellScript" --parameters file://ssm-deploy.json --query "Command.CommandId" --output text)
        for i in \$(seq 1 20); do
          STATUS=\$(aws ssm get-command-invocation --command-id "\$CMD_ID" --instance-id "${env.APP_INSTANCE_ID}" --query Status --output text 2>/dev/null || echo InProgress)
          if [ "\$STATUS" = "Success" ]; then exit 0; fi
          if [ "\$STATUS" = "Failed" ] || [ "\$STATUS" = "Cancelled" ] || [ "\$STATUS" = "TimedOut" ]; then
            echo "Despliegue via SSM fallo con estado: \$STATUS"
            exit 1
          fi
          sleep 5
        done
        echo "Timeout esperando el despliegue via SSM"
        exit 1
    """
}

// Comprueba /health y /version a traves del ALB, reintentando porque el
// target group tarda ~30-60s en marcar la instancia como healthy tras un
// despliegue (health check cada 30s, 2 comprobaciones seguidas).
void smokeTest(String expectedSha) {
    sh """
        for i in \$(seq 1 20); do
          HEALTH=\$(curl -s -o /dev/null -w '%{http_code}' "http://${env.ALB_DNS}/health" || echo 000)
          if [ "\$HEALTH" = "200" ]; then
            SHA=\$(curl -s "http://${env.ALB_DNS}/version" | sed -E 's/.*"git_sha" *: *"([^"]*)".*/\\1/')
            if [ "\$SHA" = "${expectedSha}" ]; then
              echo "Smoke test OK: /health 200, git_sha=\$SHA"
              exit 0
            fi
            echo "Healthy pero SHA todavia no coincide (\$SHA != ${expectedSha}), reintentando..."
          fi
          sleep 10
        done
        echo "Smoke test fallido: el ALB no respondio sano con el SHA esperado (${expectedSha})"
        exit 1
    """
}
