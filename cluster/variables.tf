variable "aws_region" {
  description = "AWS region where the cluster will be created"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "bottlerocket-lab"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "vpc_name" {
  description = "Name tag of the existing VPC. Used to look up the VPC ID automatically via data source."
  type        = string

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "The vpc_name variable must not be empty."
  }
}

variable "brupop_chart_version" {
  description = "Version of the Bottlerocket Update Operator helm chart"
  type        = string
  default     = "1.3.0"
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain EKS control plane logs in CloudWatch"
  type        = number
  default     = 90
}
