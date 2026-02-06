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
        sh 'ls -la'
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
