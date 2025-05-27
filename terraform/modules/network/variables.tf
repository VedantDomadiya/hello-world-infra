variable "project_name" {
  description = "Project name for tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "A map of public subnets to create. Each key is a logical name, and the value contains cidr_suffix and az_index."
  type = map(object({
    cidr_suffix = string 
    az_index    = number 
    tags        = optional(map(string), {})
  }))
}

variable "private_subnets" {
  description = "A map of private subnets to create. Each key is a logical name, and the value contains cidr_suffix and az_index."
  type = map(object({
    cidr_suffix = string 
    az_index    = number 
    tags        = optional(map(string), {})
  }))
}