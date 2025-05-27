output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of IDs of the public subnets"
  # Create a list of IDs from the map of subnet resources
  value       = [for subnet_key, subnet_obj in aws_subnet.public : subnet_obj.id]
}

output "private_subnet_ids" {
  description = "List of IDs of the private subnets"
  value       = [for subnet_key, subnet_obj in aws_subnet.private : subnet_obj.id]
}

# You might also want to output the full subnet objects or maps if needed
output "public_subnets_map" {
  description = "Map of the public subnet resources created"
  value       = aws_subnet.public
}

output "private_subnets_map" {
  description = "Map of the private subnet resources created"
  value       = aws_subnet.private
}