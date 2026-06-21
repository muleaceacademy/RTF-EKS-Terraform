# AWS and EKS
aws_region         = "ap-south-1"
cluster_name       = "mulesoft-eks-cluster"
kubernetes_version = "1.34"

# EKS worker nodes
node_instance_types = ["t3.medium"]
desired_node_count  = 3
min_node_count      = 3
max_node_count      = 3
node_disk_size      = 50

# Runtime Fabric DNS
rtf_domain = "rtf.muleaceacademy.com"

# NGINX ingress
install_nginx_ingress = true

# Runtime Fabric install orchestration
# Set to true only after you have copied activation data from Anypoint Runtime Manager.
install_runtime_fabric = false

# Do not put activation data here if this repo will go to GitHub.
# Prefer:
# export TF_VAR_rtf_activation_data='<activation-data>'
rtf_activation_data = "<activation-data>"

apply_rtf_ingress_template = false

# TLS is optional. Enable only after creating the TLS secret in rtf namespace.
enable_tls_in_rtf_template = false
rtf_tls_secret_name        = "rtf-wildcard-tls"

# Mule license
apply_mule_license = false
mule_license_file  = "/Users/abc/Documents/license.lic"

# Destroy behavior
uninstall_rtf_on_destroy = true

tags = {
  Project     = "mulesoft-rtf-eks"
  ManagedBy   = "terraform"
  Environment = "lab"
}
