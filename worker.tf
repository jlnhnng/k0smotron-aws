resource "aws_instance" "cluster-workers" {
  count         = var.worker_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.worker_flavor
  tags = {
    Name = "${var.cluster_name}-worker-${count.index + 1}",
    "Role" = "worker",
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }

  key_name                    = aws_key_pair.cluster-key.key_name
  vpc_security_group_ids      = [aws_security_group.cluster_allow_ssh.id]
  iam_instance_profile        = "${var.iam_instance_profile}"
  associate_public_ip_address = true
  source_dest_check = false
  ebs_optimized          = true
  user_data              = <<EOF
#!/bin/bash
# Use full qualified private DNS name for the host name.  Kube wants it this way.
HOSTNAME=$(curl http://169.254.169.254/latest/meta-data/hostname)
echo $HOSTNAME > /etc/hostname
sed -i "s|\(127\.0\..\.. *\)localhost|\1$HOSTNAME|" /etc/hosts
hostname $HOSTNAME
EOF

  lifecycle {
    ignore_changes = [ami]
  }

  root_block_device {
    volume_type = "gp2"
    volume_size = 50
  }
}