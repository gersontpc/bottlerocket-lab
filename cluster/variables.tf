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

variable "vpc_id" {
  description = "ID of the existing VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of existing private subnet IDs (one per availability zone: zone-a, zone-b, zone-c)"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) == 3
    error_message = "Exactly 3 private subnet IDs must be provided, one per availability zone (zone-a, zone-b, zone-c)."
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
