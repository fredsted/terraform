resource "aws_instance" "instance" {
  count = "${var.count}"

  instance_type          = "${var.instance_type}"
  ami                    = "${lookup(var.aws_amis, var.aws_region)}"
  key_name               = "${var.key_pair_id}"
  vpc_security_group_ids = ["${var.security_group_id}"]
  subnet_id              = "${var.subnet_id}"
  
  root_block_device {
      volume_size = "${var.disk_size}"
  }
  
  tags {
      Name = "${format("%s%02d", var.group_name, count.index + 1)}" # -> "backend02"
      Group = "${var.group_name}"
  }
  
  lifecycle {
    create_before_destroy = true
  }
  
  # Provisioning
  
  connection {
    user = "ubuntu"
    private_key = "${file(var.private_key_path)}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y update",
    ]
  }
}

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