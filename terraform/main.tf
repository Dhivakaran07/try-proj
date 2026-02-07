terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # ✅ Recommended for Jenkins: remote state (uncomment and fill values)
  # backend "s3" {
  #   bucket         = "YOUR_TFSTATE_BUCKET"
  #   key            = "streamline/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "YOUR_TF_LOCK_TABLE"
  #   encrypt        = true
  # }
}

############################
# VARIABLES
############################
variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for resource names"
  type        = string
  default     = "streamline"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR format, e.g. 1.2.3.4/32"
  type        = string
}

variable "db_password" {
  description = "RDS password (DO NOT HARD-CODE)"
  type        = string
  sensitive   = true
}

variable "key_name" {
  description = "Existing EC2 key pair name in this region"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

############################
# LOCALS
############################
locals {
  common_tags = {
    Project = var.project_name
    Managed = "terraform"
  }
}

############################
# PROVIDER
############################
provider "aws" {
  region = var.aws_region
}

# ✅ Use available AZs dynamically (avoids hardcoding us-east-1a/b issues)
data "aws_availability_zones" "available" {
  state = "available"
}

############################
# AMI (Latest Amazon Linux 2)
############################
data "aws_ami" "amazon_linux2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

############################
# VPC
############################
resource "aws_vpc" "streamline" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

############################
# SUBNETS
############################
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.streamline.id
  cidr_block              = element(["10.0.1.0/24", "10.0.2.0/24"], count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-${count.index + 1}"
  })
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.streamline.id
  cidr_block        = element(["10.0.3.0/24", "10.0.4.0/24"], count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-${count.index + 1}"
  })
}

############################
# INTERNET GATEWAY
############################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.streamline.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

############################
# ROUTE TABLES
############################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.streamline.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route" "public_to_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.streamline.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "private_assoc" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

############################
# SECURITY GROUPS
############################

# ALB SG: allow HTTP from anywhere
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB SG: HTTP from internet"
  vpc_id      = aws_vpc.streamline.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-alb-sg"
  })
}

# Web SG: HTTP only from ALB SG, SSH only from your IP
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Web SG: HTTP from ALB only, SSH from my IP"
  vpc_id      = aws_vpc.streamline.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-web-sg"
  })
}

# RDS SG: MySQL only from Web SG
resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "RDS SG: MySQL only from Web SG"
  vpc_id      = aws_vpc.streamline.id

  ingress {
    description     = "MySQL from Web SG only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-rds-sg"
  })
}

############################
# EC2 INSTANCES (2)
############################
resource "aws_instance" "web" {
  count         = 2
  ami           = data.aws_ami.amazon_linux2.id
  instance_type = var.instance_type

  subnet_id              = aws_subnet.public[count.index].id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = var.key_name

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-web-${count.index + 1}"
  })

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y git python3
  EOF
}

############################
# LOAD BALANCER
############################
resource "aws_lb" "alb" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb_sg.id]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-alb"
  })
}

resource "aws_lb_target_group" "tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.streamline.id

  health_check {
    path                = "/"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-tg"
  })
}

resource "aws_lb_target_group_attachment" "tg_attach" {
  count            = 2
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

############################
# RDS (MYSQL)
############################
resource "aws_db_subnet_group" "db_group" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-db-subnets"
  })
}

resource "aws_db_instance" "mysql" {
  identifier        = "${var.project_name}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "streamline"
  username = "adminuser"
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.db_group.name

  publicly_accessible = false
  skip_final_snapshot = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-mysql"
  })
}

############################
# OUTPUTS (Used by Jenkins)
############################
output "alb_dns_name" {
  value       = aws_lb.alb.dns_name
  description = "ALB DNS name (preferred output name)"
}

output "alb_dns" {
  value       = aws_lb.alb.dns_name
  description = "ALB DNS name (compat output)"
}

output "web_public_ips" {
  value       = [for i in aws_instance.web : i.public_ip]
  description = "Public IPs of web instances"
}

output "rds_endpoint" {
  value       = aws_db_instance.mysql.address
  description = "RDS endpoint"
}
