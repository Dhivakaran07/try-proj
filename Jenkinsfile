pipeline {
  agent any

  triggers {
    githubPush()
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(true)   // avoids Jenkins declarative auto-checkout + your manual checkout
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
      description: 'Used only when RUN_TERRAFORM_APPLY=true (SSH allow list). Example: 49.xx.yy.zz/32'
    )

    // ✅ NEW PARAMETER
    string(
      name: 'KEY_NAME',
      defaultValue: '',
      description: 'Existing EC2 key pair name in AWS (required for terraform apply).'
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
              set -euo pipefail

              if [ -z "${KEY_NAME}" ]; then
                echo "❌ KEY_NAME is empty. Provide an existing EC2 key pair name (EC2 > Key Pairs)."
                exit 1
              fi

              if [ "${MY_IP_CIDR}" = "YOUR.IP.ADDR/32" ]; then
                echo "❌ MY_IP_CIDR is still default. Set your real public IP in CIDR, e.g. 49.xx.yy.zz/32"
                exit 1
              fi

              terraform apply -auto-approve -input=false \
                -var "my_ip_cidr=${MY_IP_CIDR}" \
                -var "db_password=${DB_PASS}" \
                -var "key_name=${KEY_NAME}"
            '''
          }
        }
      }
    }

    stage('Generate Inventory + RDS Endpoint') {
      steps {
        dir(env.TF_DIR) {
          sh '''
            set -euo pipefail

            echo "==== Checking Terraform outputs ===="
            if ! terraform output -json >/tmp/tf_outputs.json 2>/tmp/tf_err; then
              echo "❌ Terraform outputs not available."
              echo "Terraform error:"
              cat /tmp/tf_err
              echo ""
              echo "👉 Fix: Run with RUN_TERRAFORM_APPLY=true (and set MY_IP_CIDR + KEY_NAME) OR configure a remote backend (S3) to persist state."
              exit 1
            fi

            # Extract web_public_ips and rds_endpoint safely
            IPS=$(python3 - <<'PY'
import json
data=json.load(open("/tmp/tf_outputs.json"))
if "web_public_ips" not in data:
    raise SystemExit("❌ Output 'web_public_ips' not found in state. Run terraform apply (or refresh-only) to update state.")
print("\\n".join(data["web_public_ips"]["value"]))
PY
            )

            RDS=$(python3 - <<'PY'
import json
data=json.load(open("/tmp/tf_outputs.json"))
if "rds_endpoint" not in data:
    raise SystemExit("❌ Output 'rds_endpoint' not found in state. Run terraform apply to create/update state.")
print(data["rds_endpoint"]["value"])
PY
            )

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
            set -euo pipefail

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
            set -e
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
}
