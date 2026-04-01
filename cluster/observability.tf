################################################################################
# Observability
################################################################################

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name        = var.cluster_name
    Environment = local.common_tags.Environment
  }
}
