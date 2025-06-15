terraform {
  backend "s3" {
    # bucket and region configured via terraform init -backend-config
    key    = "terraform/state"
  }
}

provider "aws" {
  region = var.aws_region
}

# ECR Repository
resource "aws_ecr_repository" "streaming_api" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {
    scan_on_push = false
  }
  
  tags = {
    Name        = var.project_name
    Environment = var.environment
  }
}

# ECR Repository Policy - Allow App Runner access
resource "aws_ecr_repository_policy" "streaming_api_policy" {
  repository = aws_ecr_repository.streaming_api.name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAppRunnerPull"
        Effect = "Allow"
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
      }
    ]
  })
}

# IAM Role for App Runner Instance
resource "aws_iam_role" "apprunner_instance_role" {
  name = "${var.project_name}-apprunner-instance-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "tasks.apprunner.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Name = "${var.project_name}-apprunner-instance-role"
    Environment = var.environment
  }
}

# IAM Role for App Runner Access (ECR access)
resource "aws_iam_role" "apprunner_access_role" {
  name = "${var.project_name}-apprunner-access-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Name = "${var.project_name}-apprunner-access-role"
    Environment = var.environment
  }
}

# IAM Policy for ECR access
resource "aws_iam_role_policy_attachment" "apprunner_access_ecr" {
  role       = aws_iam_role.apprunner_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# App Runner Service
resource "aws_apprunner_service" "streaming_api" {
  service_name = "${var.project_name}-service"
  
  source_configuration {
    auto_deployments_enabled = false
    
    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_access_role.arn
    }
    
    image_repository {
      image_identifier      = "${aws_ecr_repository.streaming_api.repository_url}:latest"
      image_repository_type = "ECR"
      
      image_configuration {
        port = "5000"
        
        runtime_environment_variables = {
          FLASK_ENV = var.environment
          PORT      = "5000"
        }
      }
    }
  }
  
  
  instance_configuration {
    cpu    = "0.25 vCPU"
    memory = "0.5 GB"
    
    instance_role_arn = aws_iam_role.apprunner_instance_role.arn
  }
  
  health_check_configuration {
    protocol            = "HTTP"
    path                = "/health"
    interval            = 20
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
  
  tags = {
    Name        = "${var.project_name}-service"
    Environment = var.environment
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.apprunner_access_ecr
  ]
}

# VPC
resource "aws_vpc" "streaming_vpc" {
    cidr_block           = var.vpc_cidr
    enable_dns_hostnames = true
    enable_dns_support   = true

    tags = {
        Name        = "${var.project_name}-vpc"
        Environment = var.environment
    }
}

# Subnet Pública
resource "aws_subnet" "public_subnet" {
    vpc_id                  = aws_vpc.streaming_vpc.id
    cidr_block              = var.public_subnet_cidr
    availability_zone       = "${var.aws_region}a"
    map_public_ip_on_launch = true

    tags = {
        Name        = "${var.project_name}-public-subnet"
        Type        = "Public"
        Environment = var.environment
    }
}

# Subnet Privada
resource "aws_subnet" "private_subnet" {
    vpc_id            = aws_vpc.streaming_vpc.id
    cidr_block        = var.private_subnet_cidr
    availability_zone = "${var.aws_region}b"

    tags = {
        Name        = "${var.project_name}-private-subnet"
        Type        = "Private"
        Environment = var.environment
    }
}

# Internet Gateway
resource "aws_internet_gateway" "streaming_igw" {
    vpc_id = aws_vpc.streaming_vpc.id

    tags = {
        Name        = "${var.project_name}-igw"
        Environment = var.environment
    }
}

  # Tabla de rutas para subnet pública
resource "aws_route_table" "public_route_table" {
    vpc_id = aws_vpc.streaming_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.streaming_igw.id
    }

    tags = {
        Name        = "${var.project_name}-public-rt"
        Environment = var.environment
    }
}

# Asociar tabla de rutas con subnet pública
resource "aws_route_table_association" "public_rta" {
    subnet_id      = aws_subnet.public_subnet.id
    route_table_id = aws_route_table.public_route_table.id
}

## RDS ##

# Security Group para RDS
resource "aws_security_group" "rds_sg" {
  name_prefix = "${var.project_name}-rds-sg"
  vpc_id      = aws_vpc.streaming_vpc.id
  description = "Security group for RDS instance"

  # Permitir tráfico PostgreSQL desde la subnet pública (donde está App Runner)
  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
  }
}

# Security Group para App Runner (referenciado arriba)
resource "aws_security_group" "apprunner_sg" {
  name_prefix = "${var.project_name}-apprunner-sg"
  vpc_id      = aws_vpc.streaming_vpc.id
  description = "Security group for App Runner to access RDS"

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-apprunner-sg"
    Environment = var.environment
  }
}

# Subnet adicional para RDS (necesita al menos 2 AZs)
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.streaming_vpc.id
  cidr_block        = var.private_subnet_2_cidr
  availability_zone = "${var.aws_region}c"

  tags = {
    Name        = "${var.project_name}-private-subnet-2"
    Type        = "Private"
    Environment = var.environment
  }
}

# DB Subnet Group (requerido para RDS)
resource "aws_db_subnet_group" "streaming_db_subnet_group" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
  }
}

# RDS Instance
resource "aws_db_instance" "streaming_database" {
  # Configuración básica
  identifier = "${var.project_name}-database"
  
  # Engine y versión
  engine         = var.db_engine          # "mysql" o "postgres"
  engine_version = var.db_engine_version  # "8.0" para MySQL o "13.7" para PostgreSQL
  
  # Tamaño y clase de instancia
  instance_class    = var.db_instance_class # "db.t3.micro" para desarrollo
  allocated_storage = var.db_allocated_storage # 20 GB mínimo
  storage_type      = "gp2"
  storage_encrypted = true
  
  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password  # En producción, usar AWS Secrets Manager
  port     = var.db_port      # 3306 para MySQL, 5432 para PostgreSQL
  
  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.streaming_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false  # ¡Importante! Mantener en false para seguridad
  
  # Backup configuration
    backup_retention_period = 1    # Solo 1 día de retención
    backup_window          = "03:00-04:00"
  
  # Monitoring
    monitoring_interval = 0
  
  tags = {
    Name        = "${var.project_name}-database"
    Environment = var.environment
  }
  
  depends_on = [
    aws_db_subnet_group.streaming_db_subnet_group,
    aws_security_group.rds_sg
  ]
}



# Outputs
output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.streaming_api.repository_url
}

output "apprunner_service_url" {
  description = "URL of the App Runner service"
  value       = aws_apprunner_service.streaming_api.service_url
}

output "apprunner_service_arn" {
  description = "ARN of the App Runner service"
  value       = aws_apprunner_service.streaming_api.arn
}

  # Outputs adicionales para VPC
output "vpc_id" {
    description = "ID of the VPC"
    value       = aws_vpc.streaming_vpc.id
}

output "public_subnet_id" {
    description = "ID of the public subnet"
    value       = aws_subnet.public_subnet.id
}

output "private_subnet_id" {
    description = "ID of the private subnet"
    value       = aws_subnet.private_subnet.id
}