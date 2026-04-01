################################################################################
# Cluster Add-ons
################################################################################

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_cluster.this,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
  ]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_cluster.this,
  ]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_cluster.this,
  ]
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_cluster.this,
  ]
}

resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = var.metrics_server_chart_version
  namespace        = "kube-system"
  create_namespace = false
  wait             = false

  values = [
    yamlencode({
      args = [
        "--kubelet-insecure-tls",
        "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
      ]
    }),
  ]

  depends_on = [
    helm_release.karpenter_resources,
  ]
}

resource "helm_release" "kube_state_metrics" {
  name             = "kube-state-metrics"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-state-metrics"
  version          = var.kube_state_metrics_chart_version
  namespace        = "kube-system"
  create_namespace = false
  wait             = false

  depends_on = [
    helm_release.karpenter_resources,
  ]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true

  values = [
    yamlencode({
      installCRDs = true
    }),
  ]

  depends_on = [
    helm_release.karpenter_resources,
  ]
}

resource "helm_release" "bottlerocket_shadow" {
  name             = "brupop-crd"
  repository       = "https://bottlerocket-os.github.io/bottlerocket-update-operator/"
  chart            = "bottlerocket-shadow"
  version          = var.brupop_crd_chart_version
  namespace        = "brupop-bottlerocket-aws"
  create_namespace = true
  wait             = true

  depends_on = [
    helm_release.cert_manager,
  ]
}

resource "helm_release" "bottlerocket_update_operator" {
  name             = "brupop"
  repository       = "https://bottlerocket-os.github.io/bottlerocket-update-operator/"
  chart            = "bottlerocket-update-operator"
  version          = var.brupop_chart_version
  namespace        = "brupop-bottlerocket-aws"
  create_namespace = true
  wait             = false

  values = [
    yamlencode({
      scheduler_cron_expression         = var.brupop_scheduler_cron_expression
      update_window_start               = var.brupop_update_window_start
      update_window_stop                = var.brupop_update_window_stop
      max_concurrent_updates            = var.brupop_max_concurrent_updates
      exclude_from_lb_wait_time_in_sec  = var.brupop_exclude_from_lb_wait_time_in_sec
    }),
  ]

  depends_on = [
    helm_release.karpenter_resources,
    helm_release.cert_manager,
    helm_release.bottlerocket_shadow,
  ]
}
