packer {
  required_plugins {
    amazon = {
      version = ">= 1.1.6"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable aws_profile {
  description = "The name of the AWS profile to use"
}
variable source_ami_owner_id {
  default = "513442679011" # GovCloud
  description = "Owner id for ami to be used as the base image.  Normally prefer images owned by amazon vs aws-marketplace"
}
variable source_ami_name_filter {
  description = "A filter string to be used to find the correct ami."
  default = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}
variable target_ami_base_name {
  default = "kube-ubuntu-22.04"
  description = "Prefix to be used for target ami name.  The date will be appended to the prefix to form the AMI name"
}

source "amazon-ebs" "ubuntu" {
  ami_name        = "${var.target_ami_base_name}-{{timestamp}}"
  ami_description = "${var.target_ami_base_name} with containerd installed"
  instance_type   = "t3.small"
  profile         = var.aws_profile
  source_ami_filter {
    filters = {
      name                = var.source_ami_name_filter
      root-device-type    = "ebs"
      virtualization-type = "hvm"
      architecture = "x86_64"
    }
    most_recent = true
    owners      = [var.source_ami_owner_id]
  }
  ssh_username = "ubuntu"
  tags = {
    Name = "${var.target_ami_base_name}-{{timestamp}}"
  }
}

build {
  name    = "kube"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]
  provisioner "shell" {
    inline = ["while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 3s; done"]
  }
  provisioner "shell" {
    script = "${path.root}/setup-containerd.sh"
  }
  provisioner "shell" {
    script = "${path.root}/install-kube.sh"
  }

}
