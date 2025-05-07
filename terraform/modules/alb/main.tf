# --- ALB Security Group ---
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for the Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ingress {
  #   description = "Allow HTTPS from anywhere"
  #   from_port   = 443
  #   to_port     = 443
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  # Egress to anywhere is typically fine for an ALB to reach target groups
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-alb-sg"
    Environment = var.environment
  }
}

# --- Application Load Balancer ---
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids # ALB must be in public subnets

  enable_deletion_protection = false # Set to true for production

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
  }
}

# --- Target Group for ECS Service ---
# This TG will be registered by the ECS service
resource "aws_lb_target_group" "ecs_app_tg" {
  name        = "${var.project_name}-app-tg"
  port        = var.container_port # Port on which tasks listen
  protocol    = "HTTP"             # Traffic from ALB to tasks is HTTP
  vpc_id      = var.vpc_id
  target_type = "ip" # For Fargate tasks

  health_check {
    enabled             = true
    path                = "/" # Your application's health check path (root path for now)
    protocol            = "HTTP"
    port                = "traffic-port" # Use the port of the target group
    matcher             = "200-399"      # Expect HTTP 200-399 for healthy
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "${var.project_name}-app-target-group"
    Environment = var.environment
  }
}

# --- ALB Listener for HTTP (Port 80) ---
# Redirects all HTTP traffic to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward" # Change to forward
    target_group_arn = aws_lb_target_group.ecs_app_tg.arn # Forward to ECS target group
  }
}

# # --- ALB Listener for HTTPS (Port 443) ---
# resource "aws_lb_listener" "https" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-2016-08" # Choose an appropriate policy
# #  certificate_arn   = var.acm_certificate_arn

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.ecs_app_tg.arn
#   }
# }