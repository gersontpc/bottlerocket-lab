################################################################################
# Existing VPC and subnets (data sources - no network resources are created).
# The control plane and Karpenter nodes use the default public subnets filtered
# by supported AZs. Fargate profiles require private subnets and can use
# explicitly provided IDs, existing private subnets, or a Terraform-managed
# private subnet + NAT path for the lab VPC.
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

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }

  filter {
    name   = "availability-zone"
    values = local.control_plane_azs
  }

  lifecycle {
    postcondition {
      condition     = length(self.ids) >= 2
      error_message = "At least two default public subnets are required in VPC '${var.vpc_name}' across these AZs: ${join(", ", local.control_plane_azs)}."
    }
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }

  filter {
    name   = "availability-zone"
    values = local.control_plane_azs
  }
}

resource "aws_subnet" "fargate_private" {
  for_each = local.use_managed_fargate_network ? {
    for index, az in local.control_plane_azs : az => {
      availability_zone = az
      cidr_block        = local.fargate_private_subnet_cidrs[index]
    }
  } : {}

  vpc_id                  = data.aws_vpc.this.id
  availability_zone       = each.value.availability_zone
  cidr_block              = each.value.cidr_block
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-fargate-private-${each.value.availability_zone}"
  })
}

resource "aws_eip" "fargate_nat" {
  count = local.use_managed_fargate_network ? 1 : 0

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-fargate-nat"
  })
}

resource "aws_nat_gateway" "fargate" {
  count = local.use_managed_fargate_network ? 1 : 0

  allocation_id = aws_eip.fargate_nat[0].id
  subnet_id     = local.nat_gateway_public_subnet_id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-fargate"
  })
}

resource "aws_route_table" "fargate_private" {
  count = local.use_managed_fargate_network ? 1 : 0

  vpc_id = data.aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-fargate-private"
  })
}

resource "aws_route" "fargate_private_default" {
  count = local.use_managed_fargate_network ? 1 : 0

  route_table_id         = aws_route_table.fargate_private[0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.fargate[0].id
}

resource "aws_route_table_association" "fargate_private" {
  for_each = local.use_managed_fargate_network ? aws_subnet.fargate_private : {}

  subnet_id      = each.value.id
  route_table_id = aws_route_table.fargate_private[0].id
}

data "aws_subnet" "explicit_fargate" {
  for_each = toset(local.use_explicit_fargate_subnets ? var.fargate_subnet_ids : [])
  id       = each.value
}

data "aws_subnet" "discovered_fargate" {
  for_each = toset(!local.use_explicit_fargate_subnets && !local.use_managed_fargate_network ? data.aws_subnets.private.ids : [])
  id       = each.value
}

resource "terraform_data" "fargate_subnet_validation" {
  input = sort(local.fargate_subnet_ids)

  lifecycle {
    precondition {
      condition     = length(local.fargate_subnet_ids) >= 2
      error_message = "At least two private subnet IDs are required for the EKS Fargate profiles. Set fargate_subnet_ids explicitly or create private subnets in VPC '${var.vpc_name}' across these AZs: ${join(", ", local.control_plane_azs)}."
    }

    precondition {
      condition = local.use_managed_fargate_network ? true : (
        local.use_explicit_fargate_subnets ?
        alltrue([for subnet in data.aws_subnet.explicit_fargate : subnet.vpc_id == data.aws_vpc.this.id]) :
        alltrue([for subnet in data.aws_subnet.discovered_fargate : subnet.vpc_id == data.aws_vpc.this.id])
      )
      error_message = "All Fargate subnet IDs must belong to VPC '${data.aws_vpc.this.id}'."
    }

    precondition {
      condition = local.use_managed_fargate_network ? true : (
        local.use_explicit_fargate_subnets ?
        alltrue([for subnet in data.aws_subnet.explicit_fargate : subnet.map_public_ip_on_launch == false]) :
        alltrue([for subnet in data.aws_subnet.discovered_fargate : subnet.map_public_ip_on_launch == false])
      )
      error_message = "EKS Fargate only supports private subnets. Ensure every subnet in fargate_subnet_ids has map_public_ip_on_launch = false."
    }

    precondition {
      condition = local.use_managed_fargate_network ? true : (
        local.use_explicit_fargate_subnets ?
        alltrue([for subnet in data.aws_subnet.explicit_fargate : contains(local.control_plane_azs, subnet.availability_zone)]) :
        alltrue([for subnet in data.aws_subnet.discovered_fargate : contains(local.control_plane_azs, subnet.availability_zone)])
      )
      error_message = "All Fargate subnet IDs must be in these AZs: ${join(", ", local.control_plane_azs)}."
    }

    precondition {
      condition = local.use_managed_fargate_network ? true : (
        local.use_explicit_fargate_subnets ?
        length(distinct([for subnet in data.aws_subnet.explicit_fargate : subnet.availability_zone])) >= 2 :
        length(distinct([for subnet in data.aws_subnet.discovered_fargate : subnet.availability_zone])) >= 2
      )
      error_message = "The EKS Fargate profiles require private subnets that span at least two availability zones."
    }
  }
}
