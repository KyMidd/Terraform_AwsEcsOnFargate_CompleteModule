# Cloudwatch to store logs
resource "aws_cloudwatch_log_group" "CloudWatchLogGroup" {
  name = "${var.ecs_name}LogGroup"

  tags = {
    Terraform = "true"
    Name      = "${var.ecs_name}LogGroup"
  }
}

# Create new IAM role for execution policy to use
resource "aws_iam_role" "ExecutionRole" {
  name = "${var.ecs_name}ExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name      = "${var.ecs_name}ExecutionRole"
    Terraform = "true"
  }
}

# Link to AWS-managed policy - AmazonECSTaskExecutionRolePolicy
resource "aws_iam_role_policy_attachment" "ExecutionRole_to_ecsTaskExecutionRole" {
  role       = aws_iam_role.ExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Construct IAM policies
locals {
  # Find all secret ARNs and output as a list
  execution_iam_secrets = try(
    flatten([
      for permission_type, permission_targets in var.execution_iam_access : [
        for secret in permission_targets : "${secret}*"
      ]
      if permission_type == "secrets"
    ]),
    # If nothing provided, default to empty set
    [],
  )

  # Final all S3 bucket ARNs and output as list
  execution_iam_s3_buckets = try(
    flatten([
      for permission_type, permission_targets in var.execution_iam_access : permission_targets if permission_type == "s3_buckets"
    ]),
    # If nothing provided, default to empty set
    [],
  )

  # Final all S3 bucket ARNs and output as list for object access
  execution_iam_s3_buckets_object_access = try(
    flatten(
      [
        for buckets in local.execution_iam_s3_buckets : "${buckets}/*"
      ]
    ),
    # If nothing provided, default to empty set
    [],
  )

  # Find all KMS CMK ARNs passed to module and output as a list
  execution_iam_kms_cmk = try(
    flatten([
      for permission_type, permission_targets in var.execution_iam_access : [
        for kms_cmk in permission_targets : kms_cmk
      ]
      if permission_type == "kms_cmk"
    ]),
    # If nothing provided, default to empty set
    [],
  )
}

# Construct the secrets policy
data "aws_iam_policy_document" "ecs_secrets_access" {
  count = local.execution_iam_secrets == [] ? 0 : 1
  statement {
    sid = "${var.ecs_name}EcsSecretAccess"
    #effect = "Allow"
    resources = local.execution_iam_secrets
    actions = [
      "secretsmanager:GetSecretValue",
    ]
  }
}

# Build role policy using data, link to role
resource "aws_iam_role_policy" "ecs_secrets_access_role_policy" {
  count  = local.execution_iam_secrets == [] ? 0 : 1
  name   = "${var.ecs_name}EcsSecretExecutionRolePolicy"
  role   = aws_iam_role.ExecutionRole.id
  policy = data.aws_iam_policy_document.ecs_secrets_access[0].json
}

# Construct the S3 bucket list policy
data "aws_iam_policy_document" "s3_bucket_list_access" {
  count = local.execution_iam_s3_buckets == [] ? 0 : 1
  statement {
    sid       = "S3ListBucketAccess"
    effect    = "Allow"
    resources = local.execution_iam_s3_buckets
    actions = [
      "s3:ListBucket",
    ]
  }
}

# Build role policy using data, link to role
resource "aws_iam_role_policy" "ecs_s3_bucket_list_access_role_policy" {
  count  = local.execution_iam_s3_buckets == [] ? 0 : 1
  name   = "${var.ecs_name}EcsS3BucketListExecutionRolePolicy"
  role   = aws_iam_role.ExecutionRole.id
  policy = data.aws_iam_policy_document.s3_bucket_list_access[0].json
}

# Construct the S3 bucket object policy
data "aws_iam_policy_document" "s3_bucket_object_access" {
  count = local.execution_iam_s3_buckets_object_access == [] ? 0 : 1
  statement {
    sid       = "S3BucketObjectAccess"
    effect    = "Allow"
    resources = local.execution_iam_s3_buckets_object_access
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
  }
}

# Build role policy using data, link to role
resource "aws_iam_role_policy" "ecs_s3_bucket_object_access_role_policy" {
  count  = local.execution_iam_s3_buckets_object_access == [] ? 0 : 1
  name   = "${var.ecs_name}EcsS3BucketObjectAccessExecutionRolePolicy"
  role   = aws_iam_role.ExecutionRole.id
  policy = data.aws_iam_policy_document.s3_bucket_object_access[0].json
}

# Construct the S3 bucket object policy
data "aws_iam_policy_document" "kms_cmk_access" {
  count = local.execution_iam_kms_cmk == [] ? 0 : 1
  statement {
    sid       = "KmsCmkAccess"
    effect    = "Allow"
    resources = local.execution_iam_kms_cmk
    actions = [
      "kms:Decrypt"
    ]
  }
}

# Build role policy using data, link to role
resource "aws_iam_role_policy" "ecs_kms_cmk_access_role_policy" {
  count  = local.execution_iam_kms_cmk == [] ? 0 : 1
  name   = "${var.ecs_name}EcsKmsCmkAccessExecutionRolePolicy"
  role   = aws_iam_role.ExecutionRole.id
  policy = data.aws_iam_policy_document.kms_cmk_access[0].json
}

# Task definition
# Will be relaunched by service frequently
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                   = "${var.ecs_name}"
  execution_role_arn       = aws_iam_role.ExecutionRole.arn
  task_role_arn            = var.task_role_arn == null ? null : var.task_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  # Fargate cpu/mem must match available options: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html
  cpu    = var.fargate_cpu
  memory = var.fargate_mem
  container_definitions = jsonencode(
    [
      {
        name        = "${var.ecs_name}"
        image       = "${var.image_ecr_url}:${var.image_tag}"
        cpu         = "${var.container_cpu}"
        memory      = "${var.container_mem}"
        essential   = true
        environment = var.task_environment_variables == [] ? null : var.task_environment_variables
        secrets     = var.task_secret_environment_variables == [] ? null : var.task_secret_environment_variables
        logConfiguration : {
          logDriver : "awslogs",
          options : {
            awslogs-group : "${var.ecs_name}LogGroup",
            awslogs-region : "${data.aws_region.current_region.name}",
            awslogs-stream-prefix : "${var.ecs_name}"
          }
        }
      }
    ]
  )

  tags = {
    Name = "${var.ecs_name}"
  }
}

# Cluster is compute that service will run on
resource "aws_ecs_cluster" "fargate_cluster" {
  name = "${var.ecs_name}Cluster"
  capacity_providers = [
    "FARGATE"
  ]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
  }
}

# Service definition, auto heals if task shuts down
resource "aws_ecs_service" "ecs_service" {
  name             = "${var.ecs_name}Service"
  cluster          = aws_ecs_cluster.fargate_cluster.id
  task_definition  = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count    = var.autoscale_task_weekday_scale_down
  launch_type      = "FARGATE"
  platform_version = "LATEST"
  network_configuration {
    subnets         = var.service_subnets
    security_groups = var.service_sg
  }

  # Ignored desired count changes live, permitting schedulers to update this value without terraform reverting
  lifecycle {
    ignore_changes = [desired_count]
  }
}

# Create autoscaling target linked to ECS
resource "aws_appautoscaling_target" "ServiceAutoScalingTarget" {
  count              = var.enable_scaling ? 1 : 0
  min_capacity       = var.autoscale_task_weekday_scale_down
  max_capacity       = var.autoscale_task_weekday_scale_up
  resource_id        = "service/${aws_ecs_cluster.fargate_cluster.name}/${aws_ecs_service.ecs_service.name}" # service/(clusterName)/(serviceName)
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  lifecycle {
    ignore_changes = [
      min_capacity,
      max_capacity,
    ]
  }
}

# Scale up weekdays at beginning of day
resource "aws_appautoscaling_scheduled_action" "WeekdayScaleUp" {
  count              = var.enable_scaling ? 1 : 0
  name               = "${var.ecs_name}ScaleUp"
  service_namespace  = aws_appautoscaling_target.ServiceAutoScalingTarget[0].service_namespace
  resource_id        = aws_appautoscaling_target.ServiceAutoScalingTarget[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ServiceAutoScalingTarget[0].scalable_dimension
  schedule           = "cron(0 5 ? * MON-FRI *)" #Every weekday at 5 a.m. PST
  timezone           = "America/Los_Angeles"

  scalable_target_action {
    min_capacity = var.autoscale_task_weekday_scale_up
    max_capacity = var.autoscale_task_weekday_scale_up
  }
}

# Scale down weekdays at end of day
resource "aws_appautoscaling_scheduled_action" "WeekdayScaleDown" {
  count              = var.enable_scaling ? 1 : 0
  name               = "${var.ecs_name}ScaleDown"
  service_namespace  = aws_appautoscaling_target.ServiceAutoScalingTarget[0].service_namespace
  resource_id        = aws_appautoscaling_target.ServiceAutoScalingTarget[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ServiceAutoScalingTarget[0].scalable_dimension
  schedule           = "cron(0 20 ? * MON-FRI *)" #Every weekday at 8 p.m. PST
  timezone           = "America/Los_Angeles"

  scalable_target_action {
    min_capacity = var.autoscale_task_weekday_scale_down
    max_capacity = var.autoscale_task_weekday_scale_down
  }
}

# Scale to 0 to refresh fleet
resource "aws_appautoscaling_scheduled_action" "Refresh" {
  count              = var.enable_scaling ? 1 : 0
  name               = "${var.ecs_name}Refresh"
  service_namespace  = aws_appautoscaling_target.ServiceAutoScalingTarget[0].service_namespace
  resource_id        = aws_appautoscaling_target.ServiceAutoScalingTarget[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ServiceAutoScalingTarget[0].scalable_dimension
  schedule           = "cron(0 0 * * ? *)" #Every day at midnight PST
  timezone           = "America/Los_Angeles"

  scalable_target_action {
    min_capacity = 0
    max_capacity = 0
  }
}

# Scale down to minimum after rebuild
resource "aws_appautoscaling_scheduled_action" "RefreshBackUp" {
  count              = var.enable_scaling ? 1 : 0
  name               = "${var.ecs_name}RefreshBackUp"
  service_namespace  = aws_appautoscaling_target.ServiceAutoScalingTarget[0].service_namespace
  resource_id        = aws_appautoscaling_target.ServiceAutoScalingTarget[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ServiceAutoScalingTarget[0].scalable_dimension
  schedule           = "cron(5 0 * * ? *)" #Every day at 12:05a PST
  timezone           = "America/Los_Angeles"

  scalable_target_action {
    min_capacity = var.autoscale_task_weekday_scale_down
    max_capacity = var.autoscale_task_weekday_scale_down
  }
}
