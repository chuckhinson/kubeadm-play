packer {
  required_plugins {
    amazon = {
      version = ">= 1.1.6"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "ubuntu" {
  ami_name        = "containerd-ubuntu-22.04-{{timestamp}}"
  ami_description = "Ubuntu-22.04 with containerd installed"
  instance_type   = "t2.micro"
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
    Name = "containerd-ubuntu-22.04-{{timestamp}}"
  }
}

build {
  name    = "containerd"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]
  provisioner "shell" {
    script = "./setup-containerd.sh"
  }

}
