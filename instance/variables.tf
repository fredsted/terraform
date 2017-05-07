variable "private_key_path" {
  description = "Enter the path to the SSH Private Key to run provisioner."
  default = "~/.ssh/id_rsa"
}

variable "aws_amis" {
  default = {
    eu-central-1 = "ami-060cde69"
  }
}

variable "disk_size" {
  default = 8
}

variable "count" {
  default = 1
}

variable "group_name" {
  description = "Group name becomes the base of the hostname of the instance"
}

variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "AWS region to launch servers."
  default     = "t2.small"
}

variable "subnet_id" {
  description = "ID of the AWS VPC subnet to use"
}

variable "key_pair_id" {
  description = "ID of the keypair to use for SSH"
}

variable "security_group_id" {
  description = "ID of the VPC security group to use for network"
}