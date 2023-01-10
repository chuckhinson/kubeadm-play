packer {
  required_plugins {
    amazon = {
      version = ">= 1.1.6"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "ubuntu" {
  ami_name        = "kube-ubuntu-22.04-{{timestamp}}"
  ami_description = "Ubuntu-22.04 with containerd installed"
  instance_type   = "t2.small"
  profile         = "k8splay"
  region          = "us-east-2"
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
      architecture = "x86_64"
    }
    most_recent = true
    owners      = ["099720109477"]
  }
  ssh_username = "ubuntu"
  tags = {
    Name = "kube-ubuntu-22.04-{{timestamp}}"
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
    script = "./setup-containerd.sh"
  }
  provisioner "shell" {
    script = "./install-kube.sh"
  }

}
