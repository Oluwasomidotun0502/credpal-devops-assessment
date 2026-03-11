terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "credpal_vpc" {
  cidr_block = "10.0.0.0/16"
  tags       = { Name = "credpal-vpc" }
}

# Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.credpal_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"   # ← add this line
  tags                    = { Name = "credpal-public-subnet" }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.credpal_vpc.id
  tags   = { Name = "credpal-gateway" }
}

# Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.credpal_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group
resource "aws_security_group" "web_sg" {
  name        = "credpal-web-sg"
  description = "Allow SSH, HTTP, HTTPS, App traffic"
  vpc_id      = aws_vpc.credpal_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Key Pair
resource "aws_key_pair" "credpal_key" {
  key_name   = "credpal-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

# EC2 Instance
resource "aws_instance" "app_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.credpal_key.key_name
  vpc_security_group_ids      = [aws_security_group.web_sg.id]

  tags = {
    Name = "credpal-app-server"
  }

  user_data = <<-EOT
              #!/bin/bash
              apt update -y
              apt install -y docker.io nginx certbot python3-certbot-nginx
              systemctl enable --now docker

              docker pull oluwasomidotun0502/credpal-app:latest
              docker run -d -p 3000:3000 --restart always oluwasomidotun0502/credpal-app:latest

              cat > /etc/nginx/sites-available/credpal <<EOF
              server {
                  listen 80;
                  server_name credpal.webredirect.org;

                  location / {
                      proxy_pass http://localhost:3000;
                      proxy_http_version 1.1;
                      proxy_set_header Upgrade \$http_upgrade;
                      proxy_set_header Connection 'upgrade';
                      proxy_set_header Host \$host;
                      proxy_cache_bypass \$http_upgrade;
                  }
              }
              EOF

              ln -s /etc/nginx/sites-available/credpal /etc/nginx/sites-enabled/
              nginx -t && systemctl restart nginx

              certbot --nginx --non-interactive --agree-tos -m anuoluwapodotun@gmail.com -d credpal.webredirect.org || true
              EOT
}

######################################
# Application Load Balancer (HTTP)
######################################

# Second public subnet (different AZ from public_subnet)
resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.credpal_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
  tags                    = { Name = "credpal-public-subnet-2" }
}

# Associate route table with second subnet
resource "aws_route_table_association" "public_rta_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# Application Load Balancer
resource "aws_lb" "app_lb" {
  name                       = "credpal-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.web_sg.id]
  subnets                    = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id]
  enable_deletion_protection = false
  tags                       = { Name = "credpal-alb" }
}

# Target group pointing to EC2 on port 3000
resource "aws_lb_target_group" "app_tg" {
  name     = "credpal-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.credpal_vpc.id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "credpal-tg" }
}

# Register EC2 instance to target group
resource "aws_lb_target_group_attachment" "app_instance_attach" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.app_server.id
  port             = 3000
}

# Listener for HTTP on port 80
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Output ALB DNS name
output "alb_dns_name" {
  value       = aws_lb.app_lb.dns_name
  description = "ALB public DNS name"
}
  
# Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}
