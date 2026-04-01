locals {
  control_plane_azs = [
    for suffix in var.control_plane_az_suffixes : "${var.aws_region}${suffix}"
  ]

  common_tags = {
    Environment = "lab"
  }

  use_explicit_fargate_subnets = length(var.fargate_subnet_ids) > 0
  use_managed_fargate_network  = !local.use_explicit_fargate_subnets && var.create_fargate_private_network

  fargate_private_subnet_cidrs = [
    for index, az in local.control_plane_azs : cidrsubnet(data.aws_vpc.this.cidr_block, 4, var.fargate_private_subnet_netnums[index])
  ]

  nat_gateway_public_subnet_id = var.nat_gateway_public_subnet_id != null ? var.nat_gateway_public_subnet_id : data.aws_subnets.public.ids[0]

  fargate_subnet_ids = local.use_explicit_fargate_subnets ? var.fargate_subnet_ids : (
    local.use_managed_fargate_network ? [for subnet in aws_subnet.fargate_private : subnet.id] : data.aws_subnets.private.ids
  )
}
