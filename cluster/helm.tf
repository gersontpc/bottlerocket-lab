################################################################################
# Bottlerocket Update Operator (brupop)
#
# Keeps Bottlerocket nodes up-to-date by coordinating OS updates across the
# cluster.  See: https://github.com/bottlerocket-os/bottlerocket-update-operator
################################################################################

resource "helm_release" "bottlerocket_update_operator" {
  name             = "brupop"
  repository       = "https://bottlerocket-os.github.io/bottlerocket-update-operator/"
  chart            = "bottlerocket-update-operator"
  version          = var.brupop_chart_version
  namespace        = "brupop-bottlerocket-aws"
  create_namespace = true

  depends_on = [aws_eks_cluster.this]
}
