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

output "public_subnet_ids" {
  description = "IDs of the public subnets used by the EKS cluster"
  value       = data.aws_subnets.public.ids
}

output "fargate_subnet_ids" {
  description = "IDs of the private subnets used by the EKS Fargate profiles"
  value       = local.fargate_subnet_ids
}

output "configure_kubectl" {
  description = "Command to configure kubectl to connect to the cluster"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.aws_region}"
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group receiving EKS control-plane logs"
  value       = aws_cloudwatch_log_group.eks.name
}

output "karpenter_namespace" {
  description = "Namespace where Karpenter is installed"
  value       = var.karpenter_namespace
}

output "karpenter_node_role_arn" {
  description = "ARN of the IAM role assumed by Karpenter-managed nodes"
  value       = aws_iam_role.node.arn
}

output "karpenter_instance_profile_name" {
  description = "Name of the IAM instance profile used by the Bottlerocket EC2NodeClass"
  value       = aws_iam_instance_profile.node.name
}

output "fargate_profile_names" {
  description = "Names of the EKS Fargate profiles used by the cluster add-ons"
  value = [
    aws_eks_fargate_profile.karpenter.fargate_profile_name,
  ]
}
