output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the EKS cluster"
  value       = aws_eks_cluster.this.version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = data.aws_vpc.this.id
}

output "configure_kubectl" {
  description = "Command to configure kubectl to connect to the cluster"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.aws_region}"
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group receiving EKS control-plane logs"
  value       = aws_cloudwatch_log_group.eks.name
}

output "eks_mcp_server_policy_arn" {
  description = "ARN of the IAM policy to attach to the principal that runs the Amazon EKS MCP Server"
  value       = aws_iam_policy.eks_mcp_server.arn
}
