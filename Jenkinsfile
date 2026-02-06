pipeline {
  agent any

  triggers {
    githubPush()
  }

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  environment {
    TF_DIR   = 'terraform'
    ANS_DIR  = 'ansible'
    APP_REPO = 'https://github.com/Dhivakaran07/try-proj.git'
  }

  parameters {
    booleanParam(
      name: 'RUN_TERRAFORM_APPLY',
      defaultValue: false,
      description: 'Set true if Jenkins should run terraform apply (needed if tfstate not on Jenkins).'
    )
    string(
      name: 'MY_IP_CIDR',
      defaultValue: 'YOUR.IP.ADDR/32',
      description: 'Used only when RUN_TERRAFORM_APPLY=true (SSH allow list).'
    )
    string(
      name: 'APP_VERSION',
      defaultValue: 'main',
      description: 'Branch/tag to deploy (main/dev/v1/v2).'
    )
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        sh 'pwd && ls -la'
      }
    }

    stage('Terraform Init') {
      steps {
        dir(env.TF_DIR) {
          sh 'terraform init -input=false'
        }
      }
    }

    stage('Terraform Apply (Optional)') {
      when {
        expression { return params.RUN_TERRAFORM_APPLY }
      }
      steps {
        withCredentials([string(credentialsId: 'rds-db-pass', variable: 'DB_PASS')]) {
          dir(env.TF_DIR) {
            sh '''
              set -e
              terraform apply -auto-approve -input=false \
                -var "my_ip_cidr=${MY_IP_CIDR}" \
                -var "db_password=${DB_PASS}"
            '''
          }
        }
      }
    }

    stage('Generate Inventory + RDS Endpoint') {
      steps {
        dir(env.TF_DIR) {
          sh '''
            set -e

            # Get public IPs of EC2 instances
            IPS=$(terraform output -json web_public_ips | python3 -c 'import sys,json; print("\\n".join(json.load(sys.stdin)))')

            # Get RDS endpoint
            RDS=$(terraform output -raw rds_endpoint)

            # Write Ansible inventory
            echo "[web]" > ../ansible/inventory.ini
            echo "${IPS}" >> ../ansible/inventory.ini

            # Save RDS endpoint in a file
            echo "${RDS}" > ../ansible/.rds_endpoint

            echo "==== Generated inventory.ini ===="
            cat ../ansible/inventory.ini
            echo "==== RDS endpoint ===="
            cat ../ansible/.rds_endpoint
          '''
        }
      }
    }

    stage('Deploy with Ansible') {
      steps {
        withCredentials([
          sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER'),
          string(credentialsId: 'rds-db-pass', variable: 'DB_PASS')
        ]) {
          sh '''
            set -e
            RDS=$(cat ansible/.rds_endpoint)

            # Use SSH key stored in Jenkins credentials
            export ANSIBLE_PRIVATE_KEY_FILE="${SSH_KEY}"

            ansible --version

            ansible-playbook -i ansible/inventory.ini ansible/playbook.yml \
              -u "${SSH_USER}" \
              -e "app_repo=${APP_REPO}" \
              -e "app_version=${APP_VERSION}" \
              -e "db_host=${RDS}" \
              -e "db_user=adminuser" \
              -e "db_name=streamline" \
              -e "db_pass=${DB_PASS}"
          '''
        }
      }
    }

    stage('Show ALB URL') {
      steps {
        dir(env.TF_DIR) {
          sh '''
            echo "==== ALB DNS ===="
            terraform output -raw alb_dns_name 2>/dev/null || terraform output -raw alb_dns 2>/dev/null || true
          '''
        }
      }
    }

  } // end stages

  post {
    success {
      echo '✅ Pipeline completed successfully.'
    }
    failure {
      echo '❌ Pipeline failed. Check the console logs above.'
    }
  }

} // end pipeline
