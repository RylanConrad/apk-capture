terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws-region
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.sftp_server.id
  allocation_id = "eipalloc-08d29111a4a5c2e6d" # Replace with your actual Allocation ID
}
# -----------------------------------------------------------
# 1. S3 Bucket
# -----------------------------------------------------------
resource "aws_s3_bucket" "sftp_data" {
  bucket_prefix = "sftp-transfer-data-"
  force_destroy = true
  # Optional: force_destroy = true (if you want terraform destroy to delete the bucket even if it has files)
}

# -----------------------------------------------------------
# 2. IAM Role & Permissions for EC2 -> S3
# -----------------------------------------------------------
resource "aws_iam_role" "ec2_s3_role" {
  name = "sftp-ec2-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_access_policy" {
  name = "s3-access-policy"
  role = aws_iam_role.ec2_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.sftp_data.arn,
          "${aws_s3_bucket.sftp_data.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "sftp_profile" {
  name = "sftp-s3-instance-profile"
  role = aws_iam_role.ec2_s3_role.name
}

# -----------------------------------------------------------
# 3. Security Group
# -----------------------------------------------------------
resource "aws_security_group" "sftp_sg" {
  name        = "sftp-transfer-sg"
  description = "Allow SSH/SFTP for EC2 Instance Connect"

  ingress {
    from_port   = 22
    to_port     = 22
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

# -----------------------------------------------------------
# 4. EC2 Instance
# -----------------------------------------------------------
resource "aws_instance" "sftp_server" {
  ami                  = "ami-0c7217cdde317cfec" # Ensure this Ubuntu 22.04 AMI matches your region
  instance_type        = "t3.micro"
  
  vpc_security_group_ids = [aws_security_group.sftp_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.sftp_profile.name

  # The user_data script runs as root on the very first boot
  user_data = <<-EOF
              #!/bin/bash
              # 1. Create the restricted user with no shell access
              useradd -m -s /bin/false transferuser
              
              # 2. Set up the SSH directory and inject the key
              mkdir -p /home/transferuser/.ssh
              echo "${var.transfer_public_key}" > /home/transferuser/.ssh/authorized_keys
              
              # 3. Set strict ownership and permissions
              chown -R transferuser:transferuser /home/transferuser/.ssh
              chmod 700 /home/transferuser/.ssh
              chmod 600 /home/transferuser/.ssh/authorized_keys
              
              # 4. Apply the SFTP restriction to the SSH daemon
              # ADDED: '-d /s3-uploads' automatically drops them into the S3 bucket folder upon login
              cat << 'SSHCONF' >> /etc/ssh/sshd_config
              
              Match User transferuser
                  ForceCommand internal-sftp -d /s3-uploads
                  AllowTcpForwarding no
                  X11Forwarding no
              SSHCONF
              
              # 5. Restart the SSH service to enforce the new rules
              systemctl restart sshd

              # 6. Install S3FS and FUSE
              apt-get update -y
              apt-get install -y s3fs fuse

              # 7. CRITICAL FIX: Allow other users to access FUSE mounts created by root
              echo "user_allow_other" >> /etc/fuse.conf

              # 8. Create the mount point for the SFTP user
              mkdir -p /home/transferuser/s3-uploads
              chown transferuser:transferuser /home/transferuser/s3-uploads

              # 9. Get the exact UID and GID of the new user to pass to S3FS
              T_UID=$(id -u transferuser)
              T_GID=$(id -g transferuser)

              # 10. Add the mount to /etc/fstab with corrected permissions
              # ADDED: 'umask=022' ensures the directory is natively writable by the transferuser
              echo "${aws_s3_bucket.sftp_data.id} /home/transferuser/s3-uploads fuse.s3fs _netdev,allow_other,iam_role=auto,uid=$T_UID,gid=$T_GID,umask=022 0 0" >> /etc/fstab

              # 11. Mount the bucket immediately
              mount -a
              EOF

  tags = {
    Name = "Secure-Static-Transfer"
  }
}

# -----------------------------------------------------------
# 5. Outputs
# -----------------------------------------------------------
output "sftp_static_ip" {
  description = "The static Elastic IP attached to the SFTP server"
  value       = aws_eip_association.eip_assoc.public_ip
}

output "s3_bucket_name" {
  value = aws_s3_bucket.sftp_data.id
}