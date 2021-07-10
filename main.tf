provider "aws" {
  region = "us-east-1"
}

# Lookup secret information, we'll use this later to extract the KMS CMK ARN so we can grant permissions to it
data "aws_secretsmanager_secret" "kms_cmk_arn" {
  arn = "kms_cmk_arn" # We look up the secret via ARN, and find the KMS CMK's ARN, referenced below
}

module "Ue1TiGitHubBuilders" {
  source        = "./modules/ecs_on_fargate"
  ecs_name      = "ResourceGroupName" # Name to use for customizing resources, permits deploying this module multiple times with different names
  image_ecr_url = "url_of_ECR" # URL of the container repo where image is stored

  task_environment_variables = [  # List of maps of environment variables to pass to container when it's spun up
    { name : "ENV1", value : "env_value1" }, # Remember these are clear-text in the console and via CLI
    { name : "ENV2", value : "env_value2" }
  ]
  task_secret_environment_variables = [ #Use this secret block for secrets, passkeys, etc.
    { name : "SECRET", valueFrom : "secrets_manager_secret_arn" } # Note we're using 'valueFrom' here, which accepts a secrets manager ARN rather than plain-text secret
  ]

  execution_iam_access = {
    secrets = [
      "secrets_manager_secret_arn" # ARN of secret to grant access to
    ]
    kms_cmk = [
      data.aws_secretsmanager_secret.kms_cmk_arn.kms_key_id # For secret encrypted with CMK, find CMK ARN and grant access
    ]
    s3_buckets = [
      "s3_bucket_arn" # S3 bucket ARN to grant access to
    ]
  }

  task_role_arn = "arn_of_task_role" # This role is used by the container that's launched

  service_subnets = [ # A list of subnets to put the fargate and container into
    var.subnet1_id,
    var.subnet2_id,
  ]
  service_sg = [ # A list of SGs to assign to the container
    var.sg_id,
  ]
}
