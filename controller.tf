resource "aws_instance" "cluster-controller" {
  count         = var.controller_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.controller_flavor

  tags = {
    Name = "${var.cluster_name}-controller-${count.index + 1}",
    "Role" = "controller+worker",
    "kubernetes.io/cluster/${var.cluster_name}" = "owned",
    "Creator" = "jhennig@mirantis.com"
  }
  key_name                    = aws_key_pair.cluster-key.key_name
  vpc_security_group_ids      = [aws_security_group.cluster_allow_ssh.id]
  iam_instance_profile        = "${var.iam_instance_profile}"
  associate_public_ip_address = true
  ebs_optimized               = true
  user_data                   = <<EOF
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

  provisioner "remote-exec" {
    inline = ["sudo mkdir -p /var/lib/k0s/manifests/aws"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.k0sctl.private_key_pem
      host        = self.public_ip
    }
  }

  provisioner "file" {
    source      = "./manifests/aws-ebs-storageclass.yaml"
    destination = "/tmp/aws-ebs-storageclass.yaml"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.k0sctl.private_key_pem
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = ["sudo mv /tmp/aws-ebs-storageclass.yaml /var/lib/k0s/manifests/aws/aws-ebs-storageclass.yaml"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.k0sctl.private_key_pem
      host        = self.public_ip
    }
  }
}