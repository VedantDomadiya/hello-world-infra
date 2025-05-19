# --- Network Module ---
module "network" {
  source = "./modules/network"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  vpc_cidr_block = var.vpc_cidr_block
  # Using default subnet counts from module variables
}

# --- ECS Module ---
# Note: We need outputs from RDS (secret ARN, SG ID) and Network (VPC ID, Subnets).
# RDS needs the ECS SG ID. This creates a cycle if defined naively.
# We define ECS first to get its SG ID, pass it to RDS, then use RDS outputs in ECS.
# Terraform handles dependency resolution based on these references.

module "ecs" {
  source = "./modules/ecs"

  project_name        = var.project_name
  environment         = var.environment
  aws_region          = var.aws_region
  vpc_id              = module.network.vpc_id
  #public_subnet_ids   = module.network.public_subnet_ids # Deploying service in public subnets
  # Launch tasks in private subnets so they can use the NAT Gateway for outbound access
  public_subnet_ids   = module.network.private_subnet_ids 
  # Note: The variable name in the ECS module is still 'public_subnet_ids', but we are passing private subnet IDs to it. You could rename the variable in the ECS module to 'task_subnet_ids' for clarity if desired.
  
  #  rds_sg_id           = module.rds.rds_sg_id      # Pass RDS SG ID for egress rule
  #  db_port             = var.db_port               # Pass DB port for egress rule
  db_secret_arn       = module.rds.db_secret_arn  # Pass Secret ARN for task definition
  container_image_uri = "${module.ecs.ecr_repository_url}:${var.container_image_tag}" # Construct image URI
  container_port      = var.container_port
  # Using default CPU/Memory/Task count from module variables
  alb_app_target_group_arn = module.alb.ecs_app_target_group_arn
  alb_security_group_id    = module.alb.alb_security_group_id

  # Explicit dependency to ensure RDS module (and its SG) is created before ECS tries to use its outputs
#  depends_on = [module.rds]
}


# --- RDS Module ---
module "rds" {
  source = "./modules/rds"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  vpc_id               = module.network.vpc_id
  private_subnet_ids   = module.network.private_subnet_ids # Deploy DB in private subnets
  #  ecs_tasks_sg_id      = module.ecs.ecs_tasks_sg_id  # Pass ECS Task SG for ingress rule
  db_name              = var.db_name
  db_username          = var.db_username
  db_instance_class    = var.db_instance_class
  db_allocated_storage = var.db_allocated_storage
  db_engine            = var.db_engine
  db_engine_version    = var.db_engine_version
  db_port              = var.db_port
  # Using default multi-az/skip-snapshot from module variables

  # Explicit dependency to ensure ECS module (and its SG) is created before RDS tries to use its outputs
#  depends_on = [module.ecs]
}

# Note on Dependency Cycle Handling:
# - ECS Module defines ECS SG and outputs its ID (`ecs_tasks_sg_id`).
# - RDS Module defines RDS SG and outputs its ID (`rds_sg_id`).
# - ECS Module takes `rds_sg_id` as input to allow egress TO RDS.
# - RDS Module takes `ecs_tasks_sg_id` as input to allow ingress FROM ECS.
# - We add explicit `depends_on` in both module calls pointing to each other.
#   Terraform is generally smart enough to resolve this based on attribute passing,
#   but explicit depends_on makes the intent clearer and can help in complex scenarios.
#   Alternatively, define the Security Group Rules connecting them here in the root module,
#   referencing `module.ecs.ecs_tasks_sg_id` and `module.rds.rds_sg_id`.

# --- ALB Module ---
module "alb" {
  source = "./modules/alb"

  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  container_port      = var.container_port
}

# --- WAF IP Set (for whitelisting) ---
resource "aws_wafv2_ip_set" "allowed_ips" {
  count = var.enable_waf && length(var.waf_allowed_ips) > 0 ? 1 : 0 # Create only if WAF enabled and IPs provided

  name               = "${var.project_name}-allowed-ips"
  scope              = "REGIONAL" # For use with Application Load Balancer
  ip_address_version = "IPV4"    # Or IPV6 if needed
  addresses          = var.waf_allowed_ips

  tags = {
    Name        = "${var.project_name}-waf-ipset"
    Environment = var.environment
  }
}

# --- WAF WebACL ---
resource "aws_wafv2_web_acl" "main" {
  count = var.enable_waf ? 1 : 0 # Create only if WAF enabled

  name  = "${var.project_name}-web-acl"
  scope = "REGIONAL"

  default_action {
    allow {} # Default to allow traffic that doesn't match any block rules
    # Or use block {} to default to block and only allow specific rules
  }

  # Example using a dynamic block for the IP set rule
  dynamic "rule" {
    for_each = length(var.waf_allowed_ips) > 0 ? [1] : [] # Add rule only if IPs are provided
    content {
      name     = "AllowSpecificIPs"
      priority = 1 # Lower numbers are evaluated first

      action {
        allow {} # Allow traffic matching this rule
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.allowed_ips[0].arn # Reference the IP set created above
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AllowSpecificIPsMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  # Example using a dynamic block for AWS Managed Rules (looping through variable)
  dynamic "rule" {
    for_each = { for idx, rule_group in var.waf_managed_rule_groups : idx => rule_group } # Iterate over the list
    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        # You can override the action of the entire rule group (e.g., to "count" instead of "block")
        # "none" means use the actions defined by the rules within the group
        dynamic "count" {
            for_each = rule.value.override_action == "count" ? [1] : []
            content {}
        }
        dynamic "none" {
            for_each = rule.value.override_action == "none" ? [1] : []
            content {}
        }
        # Add block if needed
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor_name # e.g., "AWS"
          # You can exclude specific rules within a managed rule group
          dynamic "excluded_rule" {
            for_each = rule.value.excluded_rules
            content {
                name = excluded_rule.value.name
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = substr("Metric${rule.value.name}", 0, 255) # Ensure metric name is valid
        sampled_requests_enabled   = true
      }
    }
  }


  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}WebACLMetric"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.project_name}-waf-webacl"
    Environment = var.environment
  }
}

# --- WAF WebACL Association ---
resource "aws_wafv2_web_acl_association" "alb_assoc" {
  count = var.enable_waf ? 1 : 0 # Associate only if WAF enabled

  resource_arn = module.alb.alb_arn       # ALB ARN from the alb module output
  web_acl_arn  = aws_wafv2_web_acl.main[0].arn # WebACL ARN
}