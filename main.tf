provider "aws" {
    access_key = "${var.aws_access_key}"
    secret_key = "${var.aws_secret_key}"
    region = "us-east-2"
}

resource "aws_vpc" "default" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags {
    Name = "tf_vault"
  }
}

resource "aws_subnet" "tf_vault_subnet" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true

  tags {
    Name = "tf_vault_subnet"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.default.id}"

  tags {
    Name = "tf_vault_ig"
  }
}

resource "aws_route_table" "publicaccess" {
  vpc_id = "${aws_vpc.default.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }

  tags {
    Name = "aws_route_table"
  }
}

resource "aws_route_table_association" "PublicAZA" {
  subnet_id      = "${aws_subnet.tf_vault_subnet.id}"
  route_table_id = "${aws_route_table.publicaccess.id}"
}


resource "template_file" "install" {
    template = "${file("${path.module}/scripts/install.sh.tpl")}"

    vars {
        download_url  = "${var.download-url}"
        
    }
}


// We launch Vault into an ASG so that it can properly bring them up for us.
resource "aws_autoscaling_group" "vault" {
    name = "vault-${aws_launch_configuration.vault.name}"
    launch_configuration = "${aws_launch_configuration.vault.name}"
    min_size = 1
    max_size = 2
    desired_capacity = 1
    health_check_grace_period = 15
    health_check_type = "EC2"
    vpc_zone_identifier = "${aws_subnet.tf_vault_subnet.id}"
    load_balancers = ["${aws_elb.vault.id}"]

    tag {
        key = "Name"
        value = "vault"
        propagate_at_launch = true
    }
}

resource "aws_launch_configuration" "vault" {
    image_id = "${var.ami}"
    instance_type = "${var.instance_type}"
    key_name = "${var.key-name}"
    security_groups = ["${aws_security_group.vault.id}"]
    user_data = "${template_file.install.rendered}"
}

// Security group for Vault allows SSH and HTTP access (via "tcp" in
// case TLS is used)
resource "aws_security_group" "vault" {
    name = "vault"
    description = "Vault servers"
    vpc_id = "${aws_vpc.default.id}"
}

resource "aws_security_group_rule" "vault-ssh" {
    security_group_id = "${aws_security_group.vault.id}"
    type = "ingress"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
}

// This rule allows Vault HTTP API access to individual nodes, since each will
// need to be addressed individually for unsealing.
resource "aws_security_group_rule" "vault-http-api" {
    security_group_id = "${aws_security_group.vault.id}"
    type = "ingress"
    from_port = 8200
    to_port = 8200
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "vault-egress" {
    security_group_id = "${aws_security_group.vault.id}"
    type = "egress"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
}

// Launch the ELB that is serving Vault. This has proper health checks
// to only serve healthy, unsealed Vaults.
resource "aws_elb" "vault" {
    name = "vault"
    connection_draining = true
    connection_draining_timeout = 400
    internal = true
    subnets = "${aws_subnet.tf_vault_subnet.id}"
    security_groups = ["${aws_security_group.elb.id}"]

    listener {
        instance_port = 8200
        instance_protocol = "tcp"
        lb_port = 80
        lb_protocol = "tcp"
    }

    listener {
        instance_port = 8200
        instance_protocol = "tcp"
        lb_port = 443
        lb_protocol = "tcp"
    }

    health_check {
        healthy_threshold = 2
        unhealthy_threshold = 3
        timeout = 5
        target = "${var.elb-health-check}"
        interval = 15
    }
}

resource "aws_security_group" "elb" {
    name = "vault-elb"
    description = "Vault ELB"
    vpc_id = "${aws_vpc.default.id}"
}

resource "aws_security_group_rule" "vault-elb-http" {
    security_group_id = "${aws_security_group.elb.id}"
    type = "ingress"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "vault-elb-https" {
    security_group_id = "${aws_security_group.elb.id}"
    type = "ingress"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "vault-elb-egress" {
    security_group_id = "${aws_security_group.elb.id}"
    type = "egress"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
}
