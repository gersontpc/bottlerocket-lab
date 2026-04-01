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
  default     = "1.35"
}

variable "vpc_name" {
  description = "Name tag of the existing VPC. Used to look up the VPC ID automatically via data source."
  type        = string
  default     = "default"

  validation {
    condition     = length(var.vpc_name) > 0
    error_message = "The vpc_name variable must not be empty."
  }
}

variable "control_plane_az_suffixes" {
  description = "Availability zone suffixes allowed for the EKS control plane subnets."
  type        = list(string)
  default     = ["a", "b", "c"]

  validation {
    condition     = length(var.control_plane_az_suffixes) >= 2
    error_message = "At least two availability zone suffixes are required for the EKS control plane."
  }
}

variable "fargate_subnet_ids" {
  description = "Private subnet IDs used by the Fargate profiles. Leave empty to auto-discover private subnets in the selected VPC and AZs."
  type        = list(string)
  default     = []
}

variable "create_fargate_private_network" {
  description = "Whether to create dedicated private subnets and a NAT Gateway for the EKS Fargate profiles when fargate_subnet_ids is empty."
  type        = bool
  default     = true
}

variable "fargate_private_subnet_netnums" {
  description = "Netnums used with cidrsubnet(vpc_cidr, 4, netnum) to derive the private Fargate subnet CIDRs across the selected AZs."
  type        = list(number)
  default     = [6, 7, 8]

  validation {
    condition     = length(var.fargate_private_subnet_netnums) >= length(var.control_plane_az_suffixes)
    error_message = "The fargate_private_subnet_netnums variable must contain at least one netnum per selected AZ."
  }
}

variable "nat_gateway_public_subnet_id" {
  description = "Public subnet ID used by the NAT Gateway when create_fargate_private_network is enabled. Defaults to the first selected public subnet."
  type        = string
  default     = null
}

variable "karpenter_namespace" {
  description = "Namespace where the Karpenter controller runs."
  type        = string
  default     = "karpenter"

  validation {
    condition     = length(var.karpenter_namespace) > 0
    error_message = "The karpenter_namespace variable must not be empty."
  }
}

variable "karpenter_chart_version" {
  description = "Version of the Karpenter Helm chart."
  type        = string
  default     = "1.10.0"
}

variable "karpenter_bottlerocket_ami_alias" {
  description = "Pinned AMI alias used by the Bottlerocket EC2NodeClass. For production, prefer a fixed version instead of @latest."
  type        = string
  default     = "bottlerocket@latest"

  validation {
    condition     = startswith(var.karpenter_bottlerocket_ami_alias, "bottlerocket@")
    error_message = "The karpenter_bottlerocket_ami_alias variable must start with 'bottlerocket@'."
  }
}

variable "karpenter_nodepool_cpu_limit" {
  description = "Aggregate CPU limit for the default Karpenter NodePool."
  type        = string
  default     = "6"
}

variable "karpenter_nodepool_memory_limit" {
  description = "Aggregate memory limit for the default Karpenter NodePool."
  type        = string
  default     = "24Gi"
}

variable "karpenter_instance_categories" {
  description = "Allowed EC2 instance categories for the default Karpenter NodePool."
  type        = list(string)
  default     = ["c", "m", "r"]
}

variable "karpenter_instance_sizes" {
  description = "Allowed EC2 instance sizes for the default Karpenter NodePool."
  type        = list(string)
  default     = ["medium"]
}

variable "karpenter_capacity_types" {
  description = "Allowed Karpenter capacity types for the default NodePool."
  type        = list(string)
  default     = ["on-demand"]

  validation {
    condition = alltrue([
      for value in var.karpenter_capacity_types : contains(["on-demand", "spot", "reserved"], value)
    ])
    error_message = "The karpenter_capacity_types variable must only contain on-demand, spot, or reserved."
  }
}

variable "karpenter_consolidate_after" {
  description = "Delay before Karpenter consolidates underutilized capacity."
  type        = string
  default     = "1m"
}

variable "brupop_chart_version" {
  description = "Version of the Bottlerocket Update Operator helm chart"
  type        = string
  default     = "1.8.0"
}

variable "brupop_crd_chart_version" {
  description = "Version of the Bottlerocket Shadow CRD helm chart"
  type        = string
  default     = "1.0.0"
}

variable "brupop_scheduler_cron_expression" {
  description = "Scheduler cron expression for BRUPOP maintenance windows. Use '* * * * * * *' to disable the scheduler-based window."
  type        = string
  default     = "0 0 1 * * * *"
}

variable "brupop_update_window_start" {
  description = "Deprecated BRUPOP update window start time in UTC, formatted as hour:minute:second."
  type        = string
  default     = "0:0:0"
}

variable "brupop_update_window_stop" {
  description = "Deprecated BRUPOP update window stop time in UTC, formatted as hour:minute:second."
  type        = string
  default     = "2:0:0"
}

variable "brupop_max_concurrent_updates" {
  description = "Maximum number of concurrent BRUPOP node updates. Use a positive integer encoded as string or 'unlimited'."
  type        = string
  default     = "1"
}

variable "brupop_exclude_from_lb_wait_time_in_sec" {
  description = "Seconds BRUPOP waits after excluding a node from external load balancers before draining it."
  type        = string
  default     = "0"
}

variable "metrics_server_chart_version" {
  description = "Version of the metrics-server Helm chart."
  type        = string
  default     = "3.13.0"
}

variable "kube_state_metrics_chart_version" {
  description = "Version of the kube-state-metrics Helm chart."
  type        = string
  default     = "6.1.0"
}

variable "cert_manager_chart_version" {
  description = "Version of the cert-manager Helm chart."
  type        = string
  default     = "1.20.1"
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain EKS control plane logs in CloudWatch"
  type        = number
  default     = 7
}

variable "bottlerocket_log_shipper_image" {
  description = "Container image used by the Bottlerocket host container that ships host logs to CloudWatch Logs."
  type        = string
  default     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
}

variable "bottlerocket_log_shipper_log_level" {
  description = "Fluent Bit log level used inside the Bottlerocket log-shipper host container."
  type        = string
  default     = "error"

  validation {
    condition = contains([
      "off",
      "error",
      "warn",
      "info",
      "debug",
      "trace",
    ], lower(var.bottlerocket_log_shipper_log_level))
    error_message = "The bottlerocket_log_shipper_log_level variable must be one of: off, error, warn, info, debug, trace."
  }
}

variable "bottlerocket_log_shipper_storage_backlog_mem_limit" {
  description = "Fluent Bit backlog memory cap used inside the Bottlerocket log-shipper host container. This is not a container runtime memory limit."
  type        = string
  default     = "16M"
}

variable "bottlerocket_log_shipper_input_mem_buf_limit" {
  description = "Fluent Bit input memory buffer cap used inside the Bottlerocket log-shipper host container. This is not a container runtime memory limit."
  type        = string
  default     = "16M"
}

variable "bottlerocket_log_shipper_storage_max_chunks_up" {
  description = "Maximum number of filesystem-backed chunks that Fluent Bit may keep promoted in memory before applying backpressure."
  type        = number
  default     = 64
}

variable "bottlerocket_log_shipper_output_storage_total_limit_size" {
  description = "Maximum on-disk backlog that the Bottlerocket log-shipper output may accumulate before older queued chunks are dropped."
  type        = string
  default     = "256M"
}

variable "bottlerocket_log_shipper_max_entries" {
  description = "Maximum number of journal records the Fluent Bit systemd input processes per collection cycle."
  type        = number
  default     = 1000
}

variable "bottlerocket_log_shipper_db_sync" {
  description = "SQLite sync mode used by the Fluent Bit systemd cursor database."
  type        = string
  default     = "normal"

  validation {
    condition = contains([
      "extra",
      "full",
      "normal",
      "off",
    ], lower(var.bottlerocket_log_shipper_db_sync))
    error_message = "The bottlerocket_log_shipper_db_sync variable must be one of: extra, full, normal, off."
  }
}
