variable "project_name" {
  description = "Project name for tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the ALB will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

# variable "acm_certificate_arn" {
#   description = "ARN of the ACM certificate for HTTPS listener"
#   type        = string
# }

variable "container_port" {
  description = "The port on which the application container listens"
  type        = number
  #default     = 80
}