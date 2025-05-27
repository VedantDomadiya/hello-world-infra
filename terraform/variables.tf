variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name to be used for tagging and resource naming"
  type        = string
  default     = "hello-world"
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
  default     = "dev"
}

# --- Network Module Variables ---
variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# --- RDS Module Variables ---
variable "db_name" {
  description = "Database name"
  type        = string
  default     = "webappdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "dbadmin"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS instance in GB"
  type        = number
  default     = 20
}

variable "db_engine" {
  description = "Database engine"
  type        = string
  default     = "postgres"
}

variable "db_engine_version" {
  description = "Database engine version"
  type        = string
  # Updated default to a common PostgreSQL version. Adjust if using MySQL etc.
  default     = "17" # Example: check available versions for db.t3.micro in ap-south-1
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432 # Default for PostgreSQL
}

# --- ECS Module Variables ---
# The ECR repository URL depends on the account and region,
# so we construct it in main.tf using the ECR module output.
# We'll add a variable for the image tag.
variable "container_image_tag" {
  description = "Tag of the Docker image to deploy"
  type        = string
#  default     = "latest"
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 80
}

variable "waf_custom_ip_sets" {
  description = "A map of custom IP sets to be created and used in WAF rules. Each key is a unique identifier for the IP set configuration."
  type = map(object({
    name               = string # A short name to be part of the AWS resource name, e.g., "office-ips"
    description        = optional(string, "Custom IP Set defined by Terraform")
    ip_address_version = string # Must be "IPV4" or "IPV6"
    addresses          = list(string) # List of IP addresses or CIDRs, e.g., ["1.2.3.4/32", "5.6.0.0/16"]
    rule_action        = string # WAF rule action: "allow", "block", or "count"
    rule_priority      = number # Priority for the WAF rule (lower numbers evaluated first)
  }))
  default = {} # Default to no custom IP sets
}

variable "enable_waf" {
  description = "Set to true to enable WAF and its rules."
  type        = bool
  default     = true
}

// Add this if you want to use AWS Managed Rules for WAF
variable "waf_managed_rule_groups" {
  description = "A list of AWS Managed Rule Groups to apply. See AWS documentation for names and ARNs."
  type = list(object({
    name     = string
    priority = number
    override_action = optional(string, "none") # "none", "count", "block"
    excluded_rules = optional(list(object({
      name = string
    })), [])
    vendor_name = string # e.g. "AWS"
  }))
  default = [
    {
      name        = "AWSManagedRulesCommonRuleSet"
      priority    = 10
      vendor_name = "AWS"
    },
    {
      name        = "AWSManagedRulesAmazonIpReputationList"
      priority    = 20
      vendor_name = "AWS"
    }
    # Add more managed rules here if needed
  ]
}

variable "vpc_public_subnets_config" {
  description = "Configuration for public subnets in the VPC module."
  type = map(object({
    cidr_suffix = string
    az_index    = number
    tags        = optional(map(string), {})
  }))
  default = {
    "public_az1" = { cidr_suffix = "0", az_index = 0, tags = { "NameSuffix" = "az1" } },
    "public_az2" = { cidr_suffix = "1", az_index = 1, tags = { "NameSuffix" = "az2" } }
  }
}

variable "vpc_private_subnets_config" {
  description = "Configuration for private subnets in the VPC module."
  type = map(object({
    cidr_suffix = string
    az_index    = number
    tags        = optional(map(string), {})
  }))
  default = {
    "private_az1" = { cidr_suffix = "2", az_index = 0, tags = { "NameSuffix" = "az1-private" } },
    "private_az2" = { cidr_suffix = "3", az_index = 1, tags = { "NameSuffix" = "az2-private" } }
  }
  # Ensure cidr_suffixes for private subnets do not overlap with public ones
  # and are appropriate for your VPC's cidr_block and the newbits used in cidrsubnet (e.g., 8)
}

variable "rds_custom_tags" {
  description = "Custom tags for RDS resources."
  type        = map(string)
  default     = {
    Owner = "DevTeam"
    CostCenter = "ProjectAlpha"
  }
}