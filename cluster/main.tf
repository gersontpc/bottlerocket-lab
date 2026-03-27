data "aws_caller_identity" "current" {}

################################################################################
# Existing VPC and subnets (data sources – no network resources are created)
# The VPC is looked up by its Name tag; private subnets are discovered
# automatically using the standard EKS tag kubernetes.io/role/internal-elb=1.
################################################################################

data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }

  lifecycle {
    postcondition {
      condition     = self.id != ""
      error_message = "No VPC found with Name tag '${var.vpc_name}'. Ensure the VPC exists and is tagged with Name = '${var.vpc_name}'."
    }
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  filter {
    name   = "tag:kubernetes.io/role/internal-elb"
    values = ["1"]
  }

  lifecycle {
    postcondition {
      condition     = length(self.ids) > 0
      error_message = "No private subnets found in VPC '${var.vpc_name}'. Ensure subnets are tagged with 'kubernetes.io/role/internal-elb = 1'."
    }
  }
}

################################################################################
# EKS Cluster IAM Role
################################################################################

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.cluster_name}-cluster-role"
    Environment = "lab"
  }
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSComputePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSComputePolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSBlockStoragePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSLoadBalancingPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSNetworkingPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy"
  role       = aws_iam_role.cluster.name
}

################################################################################
# EKS Node IAM Role (used by Auto Mode managed nodes)
################################################################################

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.cluster_name}-node-role"
    Environment = "lab"
  }
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodeMinimalPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryPullOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
  role       = aws_iam_role.node.name
}

################################################################################
# CloudWatch Log Group for EKS control-plane logs
# Required so the Amazon EKS MCP Server can query cluster logs for AI insights.
################################################################################

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name        = var.cluster_name
    Environment = "lab"
  }
}

################################################################################
# EKS Cluster – Auto Mode with Bottlerocket
################################################################################

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  # Required when EKS Auto Mode is enabled.
  bootstrap_self_managed_addons = false

  # Send control-plane logs to CloudWatch so the EKS MCP Server can surface
  # AI insights (health, audit, authentication, scheduling, etc.).
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  access_config {
    authentication_mode = "API"
  }

  # EKS Auto Mode: AWS fully manages compute, including Bottlerocket-based nodes,
  # node health, patching, and scaling for the selected node pools.
  compute_config {
    enabled       = true
    node_pools    = ["general-purpose", "system"]
    node_role_arn = aws_iam_role.node.arn
  }

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }

  storage_config {
    block_storage {
      enabled = true
    }
  }

  vpc_config {
    endpoint_public_access  = true
    endpoint_private_access = true
    subnet_ids              = data.aws_subnets.private.ids
  }

  tags = {
    Name        = var.cluster_name
    Environment = "lab"
  }

  depends_on = [
    aws_cloudwatch_log_group.eks,
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSComputePolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSBlockStoragePolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSLoadBalancingPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSNetworkingPolicy,
  ]
}

################################################################################
# Grant the cluster creator full admin permissions via access entry
################################################################################

resource "aws_eks_access_entry" "creator" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "creator_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_caller_identity.current.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.creator]
}

################################################################################
# IAM Policy for Amazon EKS MCP Server
#
# Grants the minimum permissions required by the EKS MCP Server to provide
# AI-driven insights about the cluster.
# Attach this policy to the IAM user / role that runs the MCP server locally.
# See: https://docs.aws.amazon.com/eks/latest/userguide/eks-mcp-introduction.html
################################################################################

resource "aws_iam_policy" "eks_mcp_server" {
  name        = "${var.cluster_name}-eks-mcp-server"
  description = "Minimum read-only permissions required by the Amazon EKS MCP Server to generate AI insights"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EksMcpServerReadOnly"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:DescribeInsight",
          "eks:ListInsights",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeRouteTables",
          "cloudformation:DescribeStacks",
          "cloudwatch:GetMetricData",
          "logs:StartQuery",
          "logs:GetQueryResults",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "eks-mcpserver:QueryKnowledgeBase",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name        = "${var.cluster_name}-eks-mcp-server"
    Environment = "lab"
  }
}
