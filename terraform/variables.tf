variable "aws_region" {
  description = "AWS region where EKS will be created."
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "mulesoft-eks-cluster"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.30"
}

variable "vpc_cidr" {
  description = "CIDR range for the EKS VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones_count" {
  description = "Number of AZs to use for subnets."
  type        = number
  default     = 3
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "desired_node_count" {
  description = "Desired number of EKS worker nodes."
  type        = number
  default     = 3
}

variable "min_node_count" {
  description = "Minimum number of EKS worker nodes."
  type        = number
  default     = 3
}

variable "max_node_count" {
  description = "Maximum number of EKS worker nodes."
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "EBS volume size in GB for each worker node."
  type        = number
  default     = 50
}

variable "rtf_domain" {
  description = "Base Runtime Fabric DNS domain, for example rtf.example.com."
  type        = string
  default     = "rtf.example.com"

  validation {
    condition     = length(trimspace(var.rtf_domain)) > 0 && !startswith(var.rtf_domain, "*.")
    error_message = "rtf_domain must be a base domain like rtf.example.com, not a wildcard value like *.rtf.example.com."
  }
}

variable "install_nginx_ingress" {
  description = "Whether Terraform should install NGINX Ingress Controller using Helm."
  type        = bool
  default     = true
}

variable "install_runtime_fabric" {
  description = "Whether Terraform should run rtfctl validate/install using local-exec."
  type        = bool
  default     = false
}

variable "rtf_activation_data" {
  description = "Runtime Fabric activation data copied from Anypoint Runtime Manager."
  type        = string
  sensitive   = true
  default     = ""
}

variable "rtf_install_trigger" {
  description = "Change this value manually if you intentionally want to re-run the Runtime Fabric local-exec install orchestration."
  type        = string
  default     = "initial-install"
}

variable "apply_rtf_ingress_template" {
  description = "Whether Terraform should apply the Runtime Fabric NGINX ingress template after Runtime Fabric install."
  type        = bool
  default     = true
}

variable "rtf_ingress_template_trigger" {
  description = "Change this value manually if you intentionally want to regenerate and reapply the Runtime Fabric NGINX ingress template."
  type        = string
  default     = "initial-template"
}

variable "enable_tls_in_rtf_template" {
  description = "Whether to include TLS section in Runtime Fabric ingress template."
  type        = bool
  default     = false
}

variable "rtf_tls_secret_name" {
  description = "TLS secret name in the rtf namespace."
  type        = string
  default     = "rtf-wildcard-tls"
}

variable "apply_mule_license" {
  description = "Whether Terraform should run rtfctl apply mule-license."
  type        = bool
  default     = false
}

variable "mule_license_file" {
  description = "Absolute path to MuleSoft license file on the machine running Terraform."
  type        = string
  default     = ""
}

variable "mule_license_trigger" {
  description = "Change this value manually if you intentionally want to re-apply the Mule license."
  type        = string
  default     = "initial-license"
}

variable "uninstall_rtf_on_destroy" {
  description = "Whether to run best-effort rtfctl uninstall during terraform destroy."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags for AWS resources."
  type        = map(string)
  default = {
    Project     = "mulesoft-rtf-eks"
    ManagedBy   = "terraform"
    Environment = "lab"
  }
}
