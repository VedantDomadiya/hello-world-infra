output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Route 53 Hosted Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "ecs_app_target_group_arn" {
  description = "ARN of the default Target Group for the ECS application"
  value       = aws_lb_target_group.ecs_app_tg.arn
}

output "alb_security_group_id" {
  description = "ID of the ALB's security group"
  value       = aws_security_group.alb_sg.id
}

# output "https_listener_arn" {
#     description = "ARN of the HTTPS listener"
#     value = aws_lb_listener.https.arn
# }