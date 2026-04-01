################################################################################
# EKS Fargate Profiles
################################################################################

resource "aws_iam_role" "fargate_pod_execution" {
  name = "${var.cluster_name}-fargate-pod-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks-fargate-pods.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-fargate-pod-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "fargate_AmazonEKSFargatePodExecutionRolePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate_pod_execution.name
}

resource "aws_eks_fargate_profile" "karpenter" {
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "karpenter"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = local.fargate_subnet_ids

  selector {
    namespace = var.karpenter_namespace
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-karpenter"
  })

  depends_on = [
    terraform_data.fargate_subnet_validation,
    aws_iam_role_policy_attachment.fargate_AmazonEKSFargatePodExecutionRolePolicy,
  ]
}
