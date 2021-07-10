# Naming variables
variable "ecs_name" {
  description = "Name primitive to use for all resources created"
}

# IAM
variable "execution_iam_access" {
  description = "A complex object describing additional access beyond AmazonECSTaskExecutionRolePolicy needed to run"
  type        = map(list(string))
}
variable "task_role_arn" {
  description = "ARN of the role to assign to the launched container"
  type        = string
  default     = null
}

# Fargate
variable "fargate_cpu" {
  description = "CPU size for fargate"
  default     = 1024
  type        = number
}
variable "fargate_mem" {
  description = "Memory to use for fargate"
  default     = 2048
  type        = number
}

# Builder container
variable "container_cpu" {
  description = "CPU to use for container, must be equal or less than fargate"
  default     = 1024
  type        = number
}
variable "container_mem" {
  description = "Memory to use for container, must be equal or less than fargate"
  default     = 2048
  type        = number
}

# Task
variable "image_ecr_url" {
  description = "URL of the ECR where the builder image is stored"
  type        = string
}
variable "image_tag" {
  description = "Tag to use when pulling ECR image"
  default     = "latest"
  type        = string
}
variable "task_environment_variables" {
  description = "Environmental variables in key/pair json encoded map"
  default     = []
}
variable "task_secret_environment_variables" {
  description = "Environmental variables in key/pair json encoded map"
  default     = []
}

# Service
variable "service_subnets" {
  description = "Subnets to put the containers in"
  type        = list(any)
}
variable "service_sg" {
  description = "Security groups to assign to builder containers"
  type        = list(any)
}

# Autoscaling
variable "enable_scaling" {
  description = "Enable automatic scaling and cycle down overnight"
  type        = bool
  default     = true
}
variable "autoscale_task_weekday_scale_down" {
  description = "Number of tasks at low periods"
  default     = 1
  type        = number
}
variable "autoscale_task_weekday_scale_up" {
  description = "Number of tasks to launch on weekdays"
  default     = 1
  type        = number
}
