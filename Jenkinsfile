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
    TF_DIR   = "terraform"
    ANS_DIR  = "ansible"
    APP_REPO = "https://github.com/Dhivakaran07/try-proj.git"
  }

  parameters {
    booleanParam(name: 'RUN_TERRAFORM_APPLY', defaultValue: false,
      description: 'Set true if you want Jenkins to run terraform apply (recommended if Jenkins has no tfstate).')
