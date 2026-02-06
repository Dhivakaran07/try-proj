terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

############################
# VARIABLES
############################
variable "my_ip_cidr" {
  description = "Your public IP in CIDR format, e.g. 1.2.3.4/32"
  type        = string
}

variable "db_password" {
  description = "RDS password (DO NOT HARD-CODE)"
  type        = string
  sensitive   = true
}

############################
# PROVIDER
############################
provider "aws" {
  region = "us-east-1"
}

############################
# VPC
############################
resource "aws_vpc" "streamline" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "streamline-vpc"
  }
}

############################
# SUBNETS
############################
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.streamline.id
  cidr_block              = element(["10.0.1.0/24", "10.0.2.0/24"], count.index)
  availability_zone       = element(["us-east-1a", "us-east-1b"], count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "streamline-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.streamline.id
  cidr_block        = element(["10.0.3.0/24", "10.0.4.0/24"], count.index)
  availability_zone = element(["us-east-1a", "us-east-1b"], count.index)
  tags = {
    Name = "streamline-private-${count.index + 1}"
  }
}

############################
# INTERNET GATEWAY
############################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.streamline.id
  tags = {
    Name = "streamline-igw"
  }
}

############################
# ROUTE TABLES
############################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.streamline.id
  tags = {
    Name = "streamline-public-rt"
  }
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
  tags = {
    Name = "streamline-private-rt"
  }
}

resource "aws_route_table_association" "private_assoc" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

############################
# SECURITY GROUPS
############################
resource "aws_security_group" "web_sg" {
  name        = "streamline-web-sg"
  description = "Web security group"
  vpc_id      = aws_vpc.streamline.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "streamline-rds-sg"
  description = "RDS security group"
  vpc_id      = aws_vpc.streamline.id

  ingress {
    description     = "MySQL Access"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
       protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

############################
# EC2 INSTANCES (2)
############################
resource "aws_instance" "web" {
  count         = 2
  ami           = "ami-0b6c6ebed2801a5cb"
  instance_type = "t3.micro"

  subnet_id              = aws_subnet.public[count.index].id
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  key_name = "streamline-key"     # <-- YOUR KEYPAIR NAME

  tags = {
    Name = "streamline-web-${count.index + 1}"
  }

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
  name               = "streamline-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.web_sg.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "streamline-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.streamline.id

  health_check {
    path = "/"
  }
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
  name       = "streamline-db-subnets"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "mysql" {
  identifier             = "streamline-mysql"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20

  db_name  = "streamline"
  username = "adminuser"
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.db_group.name

  publicly_accessible = false
  skip_final_snapshot = true
}

############################
# OUTPUTS
############################
output "alb_dns" {
  value = aws_lb.alb.dns_name
}

output "web_public_ips" {
  value = [for i in aws_instance.web : i.public_ip]
}

output "rds_endpoint" {
  value = aws_db_instance.mysql.address
}
