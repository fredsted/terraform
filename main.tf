#
# Provider. We assume access keys are provided via environment variables.
#

provider "aws" {
  region = "${var.aws_region}"
}

#
# Network. We create a VPC, gateway, subnets and security groups.
#

resource "aws_vpc" "vpc_main" {
  cidr_block = "10.0.0.0/16"
  
  enable_dns_support = true
  enable_dns_hostnames = true
  
  tags {
    Name = "Main VPC"
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.vpc_main.id}"
}

resource "aws_route" "internet_access" {
  route_table_id          = "${aws_vpc.vpc_main.main_route_table_id}"
  destination_cidr_block  = "0.0.0.0/0"
  gateway_id              = "${aws_internet_gateway.default.id}"
}

# Create a public subnet to launch our load balancers
resource "aws_subnet" "public" {
  vpc_id                  = "${aws_vpc.vpc_main.id}"
  cidr_block              = "10.0.1.0/24" # 10.0.1.0 - 10.0.1.255 (256)
  map_public_ip_on_launch = true
}

# Create a private subnet to launch our backend instances
resource "aws_subnet" "private" {
  vpc_id                  = "${aws_vpc.vpc_main.id}"
  cidr_block              = "10.0.16.0/20" # 10.0.16.0 - 10.0.31.255 (4096)
  map_public_ip_on_launch = true
}

# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "elb" {
  name        = "sec_group_elb"
  description = "Security group for public facing ELBs"
  vpc_id      = "${aws_vpc.vpc_main.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Our default security group to access the instances over SSH and HTTP
resource "aws_security_group" "default" {
  name        = "sec_group_private"
  description = "Security group for backend servers and private ELBs"
  vpc_id      = "${aws_vpc.vpc_main.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  
  # Allow all from private subnet
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${aws_subnet.private.cidr_block}"]
  }

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#
# The key pair which will be installed on the instances later.
#

resource "aws_key_pair" "auth" {
  key_name   = "default"
  public_key = "${file(var.public_key_path)}"
}

#
# Instances. Using the "instance" module.
#

module "backend_api" {
    source                 = "./instance"
    subnet_id              = "${aws_subnet.private.id}"
    key_pair_id            = "${aws_key_pair.auth.id}"
    security_group_id      = "${aws_security_group.default.id}"
    
    count                  = 2
    group_name             = "api"
}

module "backend_worker" {
    source                 = "./instance"
    subnet_id              = "${aws_subnet.private.id}"
    key_pair_id            = "${aws_key_pair.auth.id}"
    security_group_id      = "${aws_security_group.default.id}"
    
    count                  = 2
    group_name             = "worker"
    instance_type          = "t2.medium"
}

module "frontend" {
    source                 = "./instance"
    subnet_id              = "${aws_subnet.private.id}"
    key_pair_id            = "${aws_key_pair.auth.id}"
    security_group_id      = "${aws_security_group.default.id}"
    
    count                  = 2
    group_name             = "frontend"
}

module "db_mysql" {
    source                 = "./instance"
    subnet_id              = "${aws_subnet.private.id}"
    key_pair_id            = "${aws_key_pair.auth.id}"
    security_group_id      = "${aws_security_group.default.id}"
    
    count                  = 3
    disk_size              = 30
    group_name             = "mysql"
    instance_type          = "t2.medium"
}

#
# Load Balancers. Uses the instance module outputs.
#

# Public Backend ELB
resource "aws_elb" "backend" {
  name = "elb-public-backend"

  subnets         = ["${aws_subnet.public.id}", "${aws_subnet.private.id}"]
  security_groups = ["${aws_security_group.elb.id}"]
  instances       = ["${module.backend_api.instance_ids}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/healthcheck.php"
    interval            = 30
  }
}

# Public Frontend ELB
resource "aws_elb" "frontend" {
  name = "elb-public-frontend"

  subnets         = ["${aws_subnet.public.id}", "${aws_subnet.private.id}"]
  security_groups = ["${aws_security_group.elb.id}"]
  instances       = ["${module.frontend.instance_ids}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/healthcheck.php"
    interval            = 30
  }
}

# Private ELB for MySQL cluster
resource "aws_elb" "db_mysql" {
  name = "elb-private-galera"

  subnets         = ["${aws_subnet.private.id}"]
  security_groups = ["${aws_security_group.default.id}"]
  instances       = ["${module.db_mysql.instance_ids}"]
  internal        = true

  listener {
    instance_port     = 3306
    instance_protocol = "tcp"
    lb_port           = 3306
    lb_protocol       = "tcp"
  }
  
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:9222/" # Galera Clustercheck listens on HTTP/9222
    interval            = 30
  }
}
