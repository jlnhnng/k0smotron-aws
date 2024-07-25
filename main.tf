terraform {
  required_version = ">= 0.14.3"
}

provider "aws" {
  region = "${var.cluster_region}"
}

resource "tls_private_key" "k0sctl" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "cluster-key" {
  key_name   = format("%s_key", var.cluster_name)
  public_key = tls_private_key.k0sctl.public_key_openssh
}

// Save the private key to filesystem
resource "local_file" "aws_private_pem" {
  file_permission = "600"
  filename        = format("%s/%s", path.module, "aws_private.pem")
  content         = tls_private_key.k0sctl.private_key_pem
}

resource "aws_security_group" "cluster_allow_ssh" {
  name        = format("%s-allow-all", var.cluster_name)
  description = "Allow all inbound traffic"
  // vpc_id      = aws_vpc.cluster-vpc.id

  // Allow all incoming and outgoing ports.
  // TODO: need to create a more restrictive policy
  ingress {
    description = "ALL"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = format("%s-allow-all", var.cluster_name)
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_elb" "k0s_elb" {
  count = var.controller_count > 1 ? 1 : 0
  name               = "${var.cluster_name}-elb"
  availability_zones = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  cross_zone_load_balancing   = true
  idle_timeout               = 400
  connection_draining        = true
  connection_draining_timeout = 400

  listener {
    instance_port     = 6443
    instance_protocol = "tcp"
    lb_port           = 6443
    lb_protocol       = "tcp"
  }

  listener {
    instance_port     = 8132
    instance_protocol = "tcp"
    lb_port           = 8132
    lb_protocol       = "tcp"
  }

  listener {
    instance_port     = 9443
    instance_protocol = "tcp"
    lb_port           = 9443
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    target              = "TCP:6443"
    interval            = 10
  }

  tags = {
    Name = "${var.cluster_name}-elb"
  }
}

resource "aws_elb_attachment" "elb_attachment" {
  count = var.controller_count > 1 ? var.controller_count : 0
  elb = aws_elb.k0s_elb[0].id
  instance = aws_instance.cluster-controller[count.index].id

  depends_on = [aws_elb.k0s_elb]
}

resource "aws_security_group" "elb_sg" {
  count       = var.controller_count > 1 ? 1 : 0
  name        = "${var.cluster_name}-elb-sg"
  description = "ELB security group"

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8132
    to_port     = 8132
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9443
    to_port     = 9443
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

locals {
  k0s_tmpl = {
    apiVersion = "k0sctl.k0sproject.io/v1beta1"
    kind       = "cluster"
    spec = {
      hosts = [
        for host in concat(aws_instance.cluster-controller, aws_instance.cluster-workers) : {
          ssh = {
            address = host.public_ip
            user    = "ubuntu"
            keyPath = "./aws_private.pem"
          }
          installFlags = [
            "--enable-cloud-provider",
            "--kubelet-extra-args=\"--cloud-provider=external\""
          ]
          role = host.tags["Role"]
        }
      ]
      k0s = {
        version = "1.30.2+k0s.0"
        dynamicConfig = false
        config = {
          apiVersion = "k0s.k0sproject.io/v1beta1"
          kind = "Cluster"
          metadata = {
            name = "${var.cluster_name}"
          }
          spec = {
            api = {
              address = var.controller_count > 1 ? aws_elb.k0s_elb[0].dns_name : aws_instance.cluster-controller[0].public_ip
              externalAddress = var.controller_count > 1 ? aws_elb.k0s_elb[0].dns_name : aws_instance.cluster-controller[0].public_ip
              k0sApiPort = 9443
              port = 6443
              sans = [
                var.controller_count > 1 ? aws_elb.k0s_elb[0].dns_name : aws_instance.cluster-controller[0].public_ip
              ]
              tunneledNetworkingMode = false
            }
            controllerManager = {}
            installConfig = {
              users = {
                etcdUser = "etcd"
                kineUser = "kube-apiserver"
                konnectivityUser = "konnectivity-server"
                kubeAPIserverUser = "kube-apiserver"
                kubeSchedulerUser = "kube-scheduler"
              }
            }
            network = {
              provider = "calico"
              kubeProxy = {
                disabled = false
                mode = "iptables"
              }
              podCIDR = "10.244.0.0/16"
              serviceCIDR = "10.96.0.0/12"
            }
            storage = {
              type = "etcd"
            }
            telemetry = {
              enabled = true
            }
            extensions = {
              helm = {
                repositories = [
                  {
                    name = "aws-cloud-controller-manager"
                    url = "https://kubernetes.github.io/cloud-provider-aws"
                  },
                  {
                    name = "aws-ebs-csi-driver"
                    url = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
                  }
                ]
                charts = [
                  {
                    name = "a-aws-cloud-controller-manager"
                    chartname = "aws-cloud-controller-manager/aws-cloud-controller-manager"
                    namespace = "kube-system"
                    version = "0.0.8"
                    values = <<-EOT
                      args:
                        - --v=2
                        - --cloud-provider=aws
                        - --allocate-node-cidrs=false
                        - --cluster-cidr=172.20.0.0/16
                        - --cluster-name="${var.cluster_name}"
                      image:
                        repository: registry.k8s.io/provider-aws/cloud-controller-manager
                        tag: v1.26.1
                      nodeSelector:
                        node-role.kubernetes.io/control-plane: "true"
                    EOT
                  },                   
                  {
                    name = "b-aws-ebs-csi-driver"
                    chartname = "aws-ebs-csi-driver/aws-ebs-csi-driver"
                    namespace = "kube-system"
                    version = "2.17.2"
                    values = <<-EOT
                      node:
                        kubeletPath: /var/lib/k0s/kubelet
                    EOT
                  }
                ]
              }
            }
          }
        }
      }
    }
  }
}

output "k0s_cluster" {
  value = replace(yamlencode(local.k0s_tmpl), "/((?:^|\n)[\\s-]*)\"([\\w-]+)\":/", "$1$2:")
}