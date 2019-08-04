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
