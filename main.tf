provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main-vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "aws-backend"
  }
}

#create an internent gateway and attach it to VPC

resource "aws_internet_gateway" "my-igw" {
  vpc_id = aws_vpc.main-vpc.id

  tags = {
    Name = "main-igw"
  }
}

#create subnets - terraform enforces that you must have more than subnet for high availability
resource "aws_subnet" "public-subnet01" {
  vpc_id            = aws_vpc.main-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = var.region_1

  tags = {
    Name = "Public-subnet01"
  }
}

#route table for subnets
resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.main-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my-igw.id
  }


  tags = {
    Name = "route-table-subnets"
  }
}

#subent 2
resource "aws_subnet" "public-subnet02" {
  vpc_id            = aws_vpc.main-vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = var.region_2

  tags = {
    Name = "Public-subnet02"
  }
}

#route table association subnets
resource "aws_route_table_association" "subnet01-assoc" {
  subnet_id      = aws_subnet.public-subnet01.id
  route_table_id = aws_route_table.public-rt.id
}

#route table association subnet02
resource "aws_route_table_association" "subnet02-assoc" {
  subnet_id      = aws_subnet.public-subnet02.id
  route_table_id = aws_route_table.public-rt.id
}

#security group 
resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.main-vpc.id

  tags = {
    Name = "allow_tls"
  }
}

data "http" "myip" {
  url = "https://ipv4.icanhazip.com"
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = "${chomp(data.http.myip.response_body)}/32"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "Allow SSH from my dynamic IP"
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}


resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6" {
  security_group_id = aws_security_group.allow_tls.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
  description       = "Allow all outbound traffic"
}

#target group for auto scaling 
resource "aws_lb_target_group" "my-app-target-group" {
  name     = "tf-example-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main-vpc.id
}


resource "aws_lb" "my-lb" {
  name               = "my-app-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_tls.id]
  subnets            = [aws_subnet.public-subnet01.id, aws_subnet.public-subnet02.id]

  enable_deletion_protection = false


  tags = {
    Environment = "production"
  }
}


# choose your ami 
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#create-key-pair for ec2 instance ssh
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

#save the keys to local file 
resource "local_sensitive_file" "private_key" {
  filename = "ssh-key.pem"
  content  = tls_private_key.ssh_key.private_key_pem
}

# Import public key into AWS
resource "aws_key_pair" "deployer" {
  key_name   = "auto-generated-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}


# Create launch template
resource "aws_launch_template" "asg_template" {
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  # Add key_name, user_data, security_groups as needed
  vpc_security_group_ids = [aws_security_group.allow_tls.id]
  key_name               = aws_key_pair.deployer.key_name

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "ubunut-template"
    }
  }

}



# Create ASG using the launch template
resource "aws_autoscaling_group" "my-auto-scale-group" {
  desired_capacity    = 2
  max_size            = 5
  min_size            = 1
  vpc_zone_identifier = [aws_subnet.public-subnet01.id, aws_subnet.public-subnet02.id]

  launch_template {
    id      = aws_launch_template.asg_template.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.my-app-target-group.arn]
}

#subnet grouped 
resource "aws_db_subnet_group" "subnet-group" {
  name       = "main-db-subnet-group"
  subnet_ids = [aws_subnet.public-subnet01.id, aws_subnet.public-subnet02.id]
}

#RDS-security group
resource "aws_security_group" "rds-sg" {
  name   = "rds-sg"
  vpc_id = aws_vpc.main-vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.allow_tls.id] # Only allow from my instances 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] #allow outbound traffic to all addresses
  }
}



resource "aws_rds_cluster" "aurora_postgresql" {
  cluster_identifier     = "my-aurora-cluster"
  engine                 = "aurora-postgresql"
  engine_version         = "17.4"
  master_username        = var.db_username
  master_password        = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.subnet-group.name
  vpc_security_group_ids = [aws_security_group.rds-sg.id]
  skip_final_snapshot    = true
  storage_encrypted      = true
}

resource "aws_rds_cluster_instance" "instance" {
  count              = 2
  cluster_identifier = aws_rds_cluster.aurora_postgresql.id
  instance_class     = "db.r5.large"
  engine             = aws_rds_cluster.aurora_postgresql.engine
  engine_version     = aws_rds_cluster.aurora_postgresql.engine_version
}
