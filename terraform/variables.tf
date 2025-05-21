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

# variable "custom_domain_name" {
#   description = "The custom domain name for the application"
#   type        = string
#   # No default, should be provided in .tfvars
# }

# variable "route53_zone_id" {
#   description = "The Route 53 Hosted Zone ID where the custom domain record will be created."
#   type        = string
#   # No default, should be provided in .tfvars
# }

# variable "waf_allowed_ips" {
#   description = "A list of IP addresses or CIDRs to allow through WAF. Example: [\"1.2.3.4/32\", \"5.6.0.0/16\"]"
#   type        = list(string)
#   default     = [] # Defaults to no specific IPs allowed by this rule, WAF default action will apply.
# }

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
  # Example structure:
  # {
  #   "allow_office_network" = {
  #     name               = "office-network"
  #     ip_address_version = "IPV4"
  #     addresses          = ["192.0.2.0/24"]
  #     rule_action        = "allow"
  #     rule_priority      = 1
  #   },
  #   "block_specific_ips" = {
  #     name               = "specific-blocked-ips"
  #     ip_address_version = "IPV4"
  #     addresses          = ["203.0.113.42/32"]
  #     rule_action        = "block"
  #     rule_priority      = 2
  #   }
  # }
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