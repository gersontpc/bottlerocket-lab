################################################################################
# Karpenter IAM and cluster integration
################################################################################

data "aws_partition" "current" {}

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint,
  ]

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-oidc"
  })
}

resource "aws_sqs_queue" "karpenter" {
  name                      = var.cluster_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-karpenter"
  })
}

resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "EC2InterruptionPolicy"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "sqs.amazonaws.com",
          ]
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.karpenter.arn
      },
      {
        Sid       = "DenyHTTP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.karpenter.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = false
          }
        }
      },
    ]
  })
}

resource "aws_cloudwatch_event_rule" "karpenter_scheduled_change" {
  name = "${var.cluster_name}-karpenter-scheduled-change"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-karpenter-scheduled-change"
  })
}

resource "aws_cloudwatch_event_target" "karpenter_scheduled_change" {
  rule      = aws_cloudwatch_event_rule.karpenter_scheduled_change.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption" {
  name = "${var.cluster_name}-karpenter-spot-interruption"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-karpenter-spot-interruption"
  })
}

resource "aws_cloudwatch_event_target" "karpenter_spot_interruption" {
  rule      = aws_cloudwatch_event_rule.karpenter_spot_interruption.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_rebalance" {
  name = "${var.cluster_name}-karpenter-rebalance"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-karpenter-rebalance"
  })
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance" {
  rule      = aws_cloudwatch_event_rule.karpenter_rebalance.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_instance_state_change" {
  name = "${var.cluster_name}-karpenter-instance-state-change"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-karpenter-instance-state-change"
  })
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state_change" {
  rule      = aws_cloudwatch_event_rule.karpenter_instance_state_change.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_capacity_reservation_interruption" {
  name = "${var.cluster_name}-karpenter-capacity-reservation-interruption"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Capacity Reservation Instance Interruption Warning"]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-karpenter-capacity-reservation-interruption"
  })
}

resource "aws_cloudwatch_event_target" "karpenter_capacity_reservation_interruption" {
  rule      = aws_cloudwatch_event_rule.karpenter_capacity_reservation_interruption.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.cluster_name}-karpenter-node-instance-profile"
  role = aws_iam_role.node.name

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-karpenter-node-instance-profile"
  })
}

resource "aws_iam_role" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
            "${replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.karpenter_namespace}:karpenter"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-karpenter-controller"
  })
}

resource "aws_iam_policy" "karpenter_controller" {
  name        = "${var.cluster_name}-karpenter-controller"
  description = "Permissions required by the Karpenter controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceAccessActions"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}::image/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}::snapshot/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:security-group/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:subnet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:capacity-reservation/*",
        ]
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
        ]
      },
      {
        Sid      = "AllowScopedEC2LaunchTemplateAccessActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:launch-template/*"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:fleet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:volume/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:network-interface/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:launch-template/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:spot-instances-request/*",
        ]
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                      = var.cluster_name
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedResourceCreationTagging"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:fleet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:volume/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:network-interface/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:launch-template/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:spot-instances-request/*",
        ]
        Action = ["ec2:CreateTags"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                      = var.cluster_name
            "ec2:CreateAction" = [
              "RunInstances",
              "CreateFleet",
              "CreateLaunchTemplate",
            ]
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedResourceTagging"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:instance/*"
        Action   = ["ec2:CreateTags"]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
          StringEqualsIfExists = {
            "aws:RequestTag/eks:eks-cluster-name" = var.cluster_name
          }
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = [
              "eks:eks-cluster-name",
              "karpenter.sh/nodeclaim",
              "Name",
            ]
          }
        }
      },
      {
        Sid    = "AllowScopedDeletion"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:*:launch-template/*",
        ]
        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate",
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid      = "AllowPassingNodeRole"
        Effect   = "Allow"
        Resource = aws_iam_role.node.arn
        Action   = "iam:PassRole"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "ec2.amazonaws.com",
              "ec2.amazonaws.com.cn",
            ]
          }
        }
      },
      {
        Sid      = "AllowAPIServerEndpointDiscovery"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
        Action   = "eks:DescribeCluster"
      },
      {
        Sid      = "AllowInterruptionQueueActions"
        Effect   = "Allow"
        Resource = aws_sqs_queue.karpenter.arn
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
        ]
      },
      {
        Sid      = "AllowRegionalReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "ec2:DescribeCapacityReservations",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },
      {
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::parameter/aws/service/*"
        Action   = "ssm:GetParameter"
      },
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action   = "pricing:GetProducts"
      },
      {
        Sid      = "AllowUnscopedInstanceProfileListAction"
        Effect   = "Allow"
        Resource = "*"
        Action   = "iam:ListInstanceProfiles"
      },
      {
        Sid      = "AllowInstanceProfileReadActions"
        Effect   = "Allow"
        Resource = aws_iam_instance_profile.node.arn
        Action   = "iam:GetInstanceProfile"
      },
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-karpenter-controller"
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  policy_arn = aws_iam_policy.karpenter_controller.arn
  role       = aws_iam_role.karpenter_controller.name
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_chart_version
  namespace        = var.karpenter_namespace
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [
    yamlencode({
      serviceAccount = {
        name = "karpenter"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller.arn
        }
      }
      controller = {
        resources = {
          requests = {
            cpu    = "1"
            memory = "1Gi"
          }
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }
      }
      settings = {
        clusterName       = aws_eks_cluster.this.name
        interruptionQueue = aws_sqs_queue.karpenter.name
        eksControlPlane   = true
      }
    }),
  ]

  depends_on = [
    aws_eks_fargate_profile.karpenter,
    aws_iam_role_policy_attachment.karpenter_controller,
    aws_sqs_queue_policy.karpenter,
  ]
}

resource "helm_release" "karpenter_resources" {
  name      = "karpenter-resources"
  chart     = "${path.module}/charts/karpenter-resources"
  namespace = var.karpenter_namespace
  wait      = true

  values = [
    yamlencode({
      nodeClass = {
        name                     = "bottlerocket"
        amiFamily                = "Bottlerocket"
        associatePublicIPAddress = true
        instanceProfile          = aws_iam_instance_profile.node.name
        amiSelectorTerms = [
          {
            alias = var.karpenter_bottlerocket_ami_alias
          },
        ]
        subnetSelectorTerms = [
          for subnet_id in data.aws_subnets.public.ids : {
            id = subnet_id
          }
        ]
        securityGroupSelectorTerms = [
          {
            id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
          },
        ]
        tags = {
          Name        = "${var.cluster_name}-karpenter"
          Environment = local.common_tags.Environment
        }
        userData = trimspace(templatefile("${path.module}/templates/bottlerocket-user-data.toml.tftpl", {
          cluster_name              = var.cluster_name
          log_shipper_image         = var.bottlerocket_log_shipper_image
          log_shipper_user_data_b64 = base64encode(templatefile("${path.module}/templates/bottlerocket-log-shipper.conf.tftpl", {
            aws_region                         = var.aws_region
            cloudwatch_log_group_name          = aws_cloudwatch_log_group.eks.name
            db_sync                            = var.bottlerocket_log_shipper_db_sync
            input_mem_buf_limit                = var.bottlerocket_log_shipper_input_mem_buf_limit
            log_level                          = var.bottlerocket_log_shipper_log_level
            max_entries                        = var.bottlerocket_log_shipper_max_entries
            output_storage_total_limit_size    = var.bottlerocket_log_shipper_output_storage_total_limit_size
            storage_backlog_mem_limit          = var.bottlerocket_log_shipper_storage_backlog_mem_limit
            storage_max_chunks_up              = var.bottlerocket_log_shipper_storage_max_chunks_up
          }))
        }))
      }
      nodePool = {
        name = "default"
        labels = {
          os                  = "bottlerocket"
          "kubernetes.io/arch" = "arm64"
        }
        requirements = [
          {
            key      = "kubernetes.io/arch"
            operator = "In"
            values   = ["arm64"]
          },
          {
            key      = "kubernetes.io/os"
            operator = "In"
            values   = ["linux"]
          },
          {
            key      = "karpenter.sh/capacity-type"
            operator = "In"
            values   = var.karpenter_capacity_types
          },
          {
            key      = "karpenter.k8s.aws/instance-category"
            operator = "In"
            values   = var.karpenter_instance_categories
          },
          {
            key      = "karpenter.k8s.aws/instance-size"
            operator = "In"
            values   = var.karpenter_instance_sizes
          },
          {
            key      = "karpenter.k8s.aws/instance-generation"
            operator = "Gt"
            values   = ["2"]
          },
        ]
        consolidateAfter = var.karpenter_consolidate_after
        limits = {
          cpu    = var.karpenter_nodepool_cpu_limit
          memory = var.karpenter_nodepool_memory_limit
        }
      }
    }),
  ]

  depends_on = [
    helm_release.karpenter,
    aws_eks_access_entry.karpenter_nodes,
  ]
}
