# --- Network Module ---
module "network" {
  source = "./modules/network"

  project_name     = var.project_name
  environment      = var.environment
  aws_region       = var.aws_region
  vpc_cidr_block   = var.vpc_cidr_block
  public_subnets   = var.vpc_public_subnets_config  # Pass the new map variable
  private_subnets  = var.vpc_private_subnets_config # Pass the new map variable
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

  task_cpu               = var.ecs_task_cpu
  task_memory            = var.ecs_task_memory
  desired_task_count   = var.ecs_desired_task_count
  assign_public_ip       = var.ecs_assign_public_ip

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
  db_multi_az = var.db_multi_az
  db_skip_final_snapshot = var.db_skip_final_snapshot
  # Using default multi-az/skip-snapshot from module variables
  custom_tags = var.rds_custom_tags # Pass the new custom tags map
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

# --- WAF Custom IP Sets (Dynamically Created) ---
resource "aws_wafv2_ip_set" "custom_ip_sets" {
  # Create an IP set for each entry in the var.waf_custom_ip_sets map,
  # but only if var.enable_waf is true.
  for_each = var.enable_waf ? var.waf_custom_ip_sets : {}

  name               = "${var.project_name}-${each.value.name}-${var.environment}" # Ensures unique name
  description        = each.value.description
  scope              = "REGIONAL" # For Application Load Balancer
  ip_address_version = each.value.ip_address_version
  addresses          = each.value.addresses

  tags = {
    Name        = "${var.project_name}-waf-ipset-${each.key}" # each.key is e.g., "trusted_developers"
    Environment = var.environment
    RuleKey     = each.key # Store the original map key for easy reference if needed
  }
}

# --- WAF WebACL ---
resource "aws_wafv2_web_acl" "main" {
  count = var.enable_waf ? 1 : 0 # Create only if WAF enabled

  name  = "${var.project_name}-web-acl"
  scope = "REGIONAL"

  default_action {
    allow {} # Or block {} depending on your default security posture
  }

  # --- Dynamic Rules for Custom IP Sets ---
  dynamic "rule" {
    # Iterate over the aws_wafv2_ip_set resources we created.
    # 'aws_wafv2_ip_set.custom_ip_sets' will be an empty map if WAF is disabled or no custom sets are defined,
    # so this dynamic block will correctly create zero rules in that case.
    for_each = aws_wafv2_ip_set.custom_ip_sets

    # 'rule.key' will be the map key from var.waf_custom_ip_sets (e.g., "trusted_developers")
    # 'rule.value' will be the aws_wafv2_ip_set object itself (e.g., aws_wafv2_ip_set.custom_ip_sets["trusted_developers"])
    content {
      name     = "Rule-For-${replace(rule.key, "_", "-")}" # Create a unique rule name
      priority = var.waf_custom_ip_sets[rule.key].rule_priority # Get priority from the original variable map

      action {
        # Dynamically set the action based on the 'rule_action' from the variable
        dynamic "allow" {
          for_each = var.waf_custom_ip_sets[rule.key].rule_action == "allow" ? [1] : []
          content {} # Empty content block for allow
        }
        dynamic "block" {
          for_each = var.waf_custom_ip_sets[rule.key].rule_action == "block" ? [1] : []
          content {} # Empty content block for block
        }
        dynamic "count" {
          for_each = var.waf_custom_ip_sets[rule.key].rule_action == "count" ? [1] : []
          content {} # Empty content block for count
        }
      }

      statement {
        ip_set_reference_statement {
          arn = rule.value.arn # Use the ARN of the IP set created in the loop
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "Metric-For-${replace(rule.key, "_", "-")}"
        sampled_requests_enabled   = true
      }
    }
  }

  # --- Dynamic Rules for AWS Managed Rule Groups (if you're using them) ---
  dynamic "rule" {
    for_each = { for idx, rg_config in var.waf_managed_rule_groups : "ManagedRule${idx}" => rg_config }
    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        dynamic "count" {
          for_each = rule.value.override_action == "count" ? [1] : []
          content {}
        }
        dynamic "none" {
          for_each = rule.value.override_action == "none" ? [1] : []
          content {}
        }
        # Add block if you want to allow overriding to block
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor_name
          dynamic "excluded_rule" {
            for_each = rule.value.excluded_rules != null ? rule.value.excluded_rules : []
            content {
              name = excluded_rule.value.name
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = substr("Metric${rule.value.name}", 0, 255) # Ensure valid metric name
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