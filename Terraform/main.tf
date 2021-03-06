# Specify the provider and access details
provider "aws" {
  shared_credentials_file = "${var.shared_credentials_file}"
  region = "${var.region}"
  profile = "terraform"
}

# Create a VPC to launch our instances into
resource "aws_vpc" "default" {
  cidr_block = "192.168.0.0/16"
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

# Create a subnet to launch our instances into
resource "aws_subnet" "default" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "192.168.38.0/24"
  map_public_ip_on_launch = true
}

# Our default security group for the logger host
resource "aws_security_group" "logger" {
  name        = "logger_security_group"
  description = "DetectionLab: Security Group for the logger host"
  vpc_id      = "${aws_vpc.default.id}"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = "${var.ip_whitelist}"
  }

  # Splunk access
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = "${var.ip_whitelist}"
  }

  # Fleet access
  ingress {
    from_port   = 8412
    to_port     = 8412
    protocol    = "tcp"
    cidr_blocks = "${var.ip_whitelist}"
  }

  # Caldera access
  ingress {
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = "${var.ip_whitelist}"
  }

  # Allow all traffic from the private subnet
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["192.168.38.0/24"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "windows" {
  name        = "windows_security_group"
  description = "DetectionLab: Security group for the Windows hosts"
  vpc_id      = "${aws_vpc.default.id}"

  # RDP
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = "${var.ip_whitelist}"
  }

  # WinRM
  ingress {
    from_port   = 5985
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = "${var.ip_whitelist}"
  }

  # Windows ATA
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = "${var.ip_whitelist}"
  }

  # Allow all traffic from the private subnet
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["192.168.38.0/24"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "auth" {
  key_name   = "${var.public_key_name}"
  public_key = "${file("${var.public_key_path}")}"
}

resource "aws_instance" "logger" {
  instance_type = "t2.medium"
  ami = "ami-0ad16744583f21877"
  tags {
    Name = "logger"
  }
  subnet_id = "${aws_subnet.default.id}"
  vpc_security_group_ids = ["${aws_security_group.logger.id}"]
  key_name = "${aws_key_pair.auth.key_name}"
  private_ip = "192.168.38.105"
  # Provision the AWS Ubuntu 16.04 AMI from scratch.
  provisioner "remote-exec" {
    inline = [
      "sudo add-apt-repository universe && sudo apt-get update && sudo apt-get install -y git",
      "echo 'logger' | sudo tee /etc/hostname && sudo hostnamectl set-hostname logger",
      "sudo adduser --disabled-password --gecos \"\" vagrant && echo 'vagrant:vagrant' | sudo chpasswd",
      "echo 'vagrant    ALL=(ALL:ALL) NOPASSWD:ALL' | sudo tee -a /etc/sudoers",
      "sudo git clone https://github.com/clong/DetectionLab.git /opt/DetectionLab",
      "sudo sed -i \"s#sed -i 's/archive.ubuntu.com/us.archive.ubuntu.com/g' /etc/apt/sources.list##g\" /opt/DetectionLab/Vagrant/bootstrap.sh",
      "sudo sed -i 's/eth1/eth0/g' /opt/DetectionLab/Vagrant/bootstrap.sh",
      "sudo sed -i 's/ETH1/ETH0/g' /opt/DetectionLab/Vagrant/bootstrap.sh",
      "sudo sed -i 's#/usr/local/go/bin/go get -u#GOPATH=/root/go /usr/local/go/bin/go get -u#g' /opt/DetectionLab/Vagrant/bootstrap.sh",
      "sudo sed -i 's#/vagrant/resources#/opt/DetectionLab/Vagrant/resources#g' /opt/DetectionLab/Vagrant/bootstrap.sh",
      "sudo chmod +x /opt/DetectionLab/Vagrant/bootstrap.sh",
      "sudo apt-get update",
      "sudo /opt/DetectionLab/Vagrant/bootstrap.sh",
      "sudo pip3.6 install --upgrade --force-reinstall pip==9.0.3 && sudo pip3.6 install -r /home/vagrant/caldera/caldera/requirements.txt && sudo pip3.6 install --upgrade pip",
      "sudo service caldera stop && sudo service caldera start"
    ]
    connection {
      type = "ssh"
      user = "ubuntu"
      private_key = "${file("${var.private_key_path}")}"
    }
  }
  root_block_device {
    delete_on_termination = true
    volume_size = 64
  }
}

resource "aws_instance" "dc" {
  instance_type = "t2.medium"
  ami = "${data.aws_ami.dc_ami.image_id}"
  tags {
    Name = "dc.windomain.local"
  }
  subnet_id = "${aws_subnet.default.id}"
  vpc_security_group_ids = ["${aws_security_group.windows.id}"]
  private_ip = "192.168.38.102"
  provisioner "remote-exec" {
    connection = {
      type     = "winrm"
      user     = "vagrant"
      password = "vagrant"
      agent    = "false"
      insecure = "true"
    }
    inline = [
      "powershell -command \"$newDNSServers = @('192.168.38.102','8.8.8.8'); $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.IPAddress -match '192.168.38.'}; $adapters | ForEach-Object {$_.SetDNSServerSearchOrder($newDNSServers)}\"",
    ]
  }
  root_block_device {
    delete_on_termination = true
  }
}

resource "aws_instance" "wef" {
  instance_type = "t2.medium"
  ami = "${data.aws_ami.wef_ami.image_id}"
  tags {
    Name = "wef.windomain.local"
  }
  subnet_id = "${aws_subnet.default.id}"
  vpc_security_group_ids = ["${aws_security_group.windows.id}"]
  private_ip = "192.168.38.103"
  provisioner "remote-exec" {
    connection = {
      type     = "winrm"
      user     = "vagrant"
      password = "vagrant"
      agent    = "false"
      insecure = "true"
    }
    inline = [
      "powershell -command \"$newDNSServers = @('192.168.38.102','8.8.8.8'); $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.IPAddress -match '192.168.38.'}; $adapters | ForEach-Object {$_.SetDNSServerSearchOrder($newDNSServers)}\"",
    ]
  }
  root_block_device {
    delete_on_termination = true
  }
}

resource "aws_instance" "win10" {
  instance_type = "t2.medium"
  ami = "${data.aws_ami.win10_ami.image_id}"
  tags {
    Name = "win10.windomain.local"
  }
  subnet_id = "${aws_subnet.default.id}"
  vpc_security_group_ids = ["${aws_security_group.windows.id}"]
  private_ip = "192.168.38.104"
  provisioner "remote-exec" {
    connection = {
      type     = "winrm"
      user     = "vagrant"
      password = "vagrant"
      agent    = "false"
      insecure = "true"
    }
    inline = [
      "powershell -command \"$newDNSServers = @('192.168.38.102','8.8.8.8'); $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.IPAddress -match '192.168.38.'}; $adapters | ForEach-Object {$_.SetDNSServerSearchOrder($newDNSServers)}\"",
    ]
  }
  root_block_device {
    delete_on_termination = true
  }
}
