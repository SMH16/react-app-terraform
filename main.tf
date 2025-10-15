data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  # public_key = file(var.ssh_public_key_path)
  public_key = <<EOF
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDogjwS+tbhxxP+wu+wC0sUNH9TPxu7pwzlLYkwgs/rY4TqreJm2lSYs8BnG8+uv/AyHuKTuyO81w2Ofp2kaavMXgFBxo57nfvzPO2iTb04S5If2aQdHW2/mYUw45n8w5mRgis4h36OLhVxw9aoCGhA/nhua+QmFckvxc3F961pk8X44wvxg0cGlp1ovx11EId575CfgQCQiczQ4nQUMNoxj36cZ+YJeBnPd94TtMQVPmpjdF616QbaNIJxrT3OU0hcPQ2GLaxzu3GZsM3vUfUr41m2hl9r+vQMEED+cw5ivS102/gnrNuRbFL91zEPPipK3cBov4VufrBaVpSKFzuq7YIie09kbgfZX89id46+Shzcgi0Kc229pguPlpa7mhGZAC+J+wHI0o6M+T4JMwcWHYv3vqLtylSA5r3MtoJLDM4i1Jv998T2kRs+mG6N66qIvZNeGHQ2yHRgxI+cUU9HFSimQLjlrN8gogo2drE99nsQS8lZ+PKlJCw8gdNqx/ItSOkeRAhCUkbkPy8r21PTE5CJbL4mGDp3jX7DeI9ipJ2BWIBRYoJPqC+Ol/dyCWomarog1mJ1zeOu2zuLDjBrf74N35o43zX5Lh5yecomxpb/eJf4ezR37E/ZWVriBEQugZbRloAzTVSedIBDc8PTxLQbFpIqGB95tgPiWlwnHQ== user@USER
EOF
}

resource "aws_security_group" "react_sg" {
  name        = "react-ec2-sg"
  description = "Allow SSH, HTTP, HTTPS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_instance" "react_ec2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.react_sg.id]
  subnet_id              = data.aws_subnets.default.ids[0]
  associate_public_ip_address = true
  tags = {
    Name = "react-ec2"
  }

  # Basic bootstrap: install nginx, node (example). When using GitHub Actions method
  # we will deploy artifact to /var/www/react-app.
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y nginx git build-essential
              # Install Node 18 (adjust version if needed)
              curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
              apt-get install -y nodejs
              # create app dir (GitHub Actions will upload build)
              mkdir -p /var/www/react-app
              chown -R ubuntu:ubuntu /var/www/react-app || true
              # make nginx proxy config placeholder
              cat > /etc/nginx/sites-available/react_app <<'NGINX'
              server {
                listen 80;
                server_name _;
                root /var/www/react-app;
                index index.html;
                location / {
                  try_files $uri /index.html;
                }
              }
              NGINX
              ln -sf /etc/nginx/sites-available/react_app /etc/nginx/sites-enabled/react_app
              rm -f /etc/nginx/sites-enabled/default
              systemctl restart nginx
              EOF
}

output "ec2_public_ip" {
  value = aws_instance.react_ec2.public_ip
}
