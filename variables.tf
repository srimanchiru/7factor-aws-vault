//-------------------------------------------------------------------
// Vault settings
//-------------------------------------------------------------------

variable "download-url" {
    default = "https://releases.hashicorp.com/vault/0.10.3/vault_0.10.3_linux_amd64.zip"
    description = "URL to download Vault"
}

//-------------------------------------------------------------------
// AWS settings
//-------------------------------------------------------------------

variable "ami" {
    default = "ami-5e8bb23b"
    description = "AMI for Vault instances"
}


variable "elb-health-check" {
    default = "HTTP:8200/v1/sys/health"
    description = "Health check for Vault servers"
}

variable "instance_type" {
    default = "t2.micro"
    description = "Instance type for Vault instances"
}

variable "key-name" {
    default = "pubkey"
    description = "SSH key name for Vault instances"
}


variable "extra-install" {
    default = ""
    description = "Extra commands to run in the install script"
}

variable "aws_access_key" { default = "" }
variable "aws_secret_key" { default = "" }
