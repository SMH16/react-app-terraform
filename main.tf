# Security group to allow SSH, HTTP, HTTPS
resource "aws_security_group" "web_sg" {
  name        = "react-web-sg"
  description = "Allow inbound traffic for web and SSH"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict to your IP for production
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

# EC2 instance
resource "aws_instance" "react_app" {
  ami           = data.aws_ami.oct15_ami
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_sg.name]

  # User data script to automate setup: install deps, clone repo, build, serve with Nginx
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y git nodejs nginx

    # Install npm and pm2 (for running if needed, but we'll use Nginx for static serve)
    curl -sL https://rpm.nodesource.com/setup_20.x | bash -
    yum install -y nodejs
    npm install -g pm2  # Optional, for process management if dynamic parts

    # Clone GitHub repo
    git clone ${var.github_repo_url} /home/ec2-user/my-react-app

    # Build React app
    cd /home/ec2-user/my-react-app
    npm install
    npm run build

    # Configure Nginx to serve the build
    rm -rf /usr/share/nginx/html/*
    cp -r build/* /usr/share/nginx/html/

    # Nginx config for React SPA (handle client-side routing)
    cat > /etc/nginx/conf.d/react.conf <<EOC
    server {
        listen 80;
        server_name _;
        root /usr/share/nginx/html;
        index index.html index.htm;

        location / {
            try_files \$uri /index.html;
        }
    }
    EOC

    # Start Nginx
    systemctl start nginx
    systemctl enable nginx
  EOF

  tags = {
    Name = "ReactAppInstance"
  }
}

# Output the public IP
output "public_ip" {
  value = aws_instance.react_app.public_ip
}