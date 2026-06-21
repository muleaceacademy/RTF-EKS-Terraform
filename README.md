# MuleSoft Runtime Fabric on AWS EKS using Terraform

This repository provisions an AWS EKS cluster and installs the Kubernetes foundation required for MuleSoft Runtime Fabric using Terraform.

It includes Terraform scripts for:

- AWS VPC creation
- AWS EKS cluster creation
- EKS managed node group with 3 worker nodes
- NGINX Ingress Controller installation using the Terraform Helm provider
- Runtime Fabric installation orchestration using `rtfctl`
- Mule license application using `rtfctl`
- Runtime Fabric NGINX ingress template creation
- Safe uninstall and infrastructure cleanup

> Important: Terraform can provision AWS and Kubernetes resources cleanly. MuleSoft Runtime Fabric still requires activation data generated from Anypoint Platform Runtime Manager. This repository accepts that activation data as a Terraform variable and executes `rtfctl validate` and `rtfctl install` from your local machine.

---

## Repository Structure

```text
.
├── README.md
├── terraform
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── locals.tf
│   ├── main.tf
│   ├── ingress-nginx.tf
│   ├── runtime-fabric.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── scripts
│   ├── install-prerequisites-mac.sh
│   ├── terraform-apply.sh
│   └── terraform-destroy.sh
├── manifests
│   └── rtf-nginx-ingress-template.yaml
└── docs
    ├── architecture.md
    ├── troubleshooting.md
    ├── production-hardening.md
    └── terraform-design-notes.md
```
---
## Simplified view of this project
```text
terraform.tfvars
   ↓
variables.tf
   ↓
locals.tf
   ↓
main.tf
   ├── VPC module
   └── EKS module
        ↓
providers.tf
   ├── AWS Provider
   ├── Kubernetes Provider
   └── Helm Provider
        ↓
ingress-nginx.tf
   └── NGINX Ingress Controller
        ↓
runtime-fabric.tf
   └── local-exec → rtfctl validate/install
        ↓
outputs.tf
```
For learning, this can be reduced into three files:
```text
- main.tf
- variables.tf
- outputs.tf
```

---

Instead of manually writing hundreds of Terraform resources for VPC, route tables, IAM roles, security groups, EKS cluster, node groups, and KMS keys, the module manages them for you.

Your project structure is:
```text
Root Terraform Module
│
├── VPC Module
│   ├── VPC
│   ├── Subnets
│   ├── NAT Gateway
│   └── Route tables
│
└── EKS Module
    ├── EKS control plane
    ├── Managed worker nodes
    ├── IAM roles
    ├── Security groups
    └── KMS encryption
```
A module does not mean “one AWS resource.” A module is a reusable collection of related resources.

---

## Architecture

```text
Developer Mac
   |
   | terraform apply
   v
AWS Account
   |
   +-- VPC
   |    +-- Public Subnets
   |    +-- Private Subnets
   |    +-- NAT Gateway
   |
   +-- EKS Cluster
        |
        +-- Managed Node Group: 3 nodes
        |
        +-- NGINX Ingress Controller
        |     +-- AWS LoadBalancer Service
        |
        +-- MuleSoft Runtime Fabric
              +-- rtf namespace
              +-- Runtime Fabric agent/operator components
              +-- Mule applications after deployment from Anypoint Runtime Manager
```

Traffic flow after Mule app deployment:

```text
Client
  ↓
DNS Record, for example *.rtf.muleaceacademy.com
  ↓
AWS Load Balancer created for NGINX Ingress Controller
  ↓
NGINX Ingress Controller
  ↓
Runtime Fabric generated Ingress
  ↓
Mule App Service
  ↓
Mule App Pod
```

---

## Prerequisites

### Local Mac tools

Install prerequisites:

```bash
chmod +x scripts/install-prerequisites-mac.sh
./scripts/install-prerequisites-mac.sh
```

The script installs or validates:

- Homebrew
- AWS CLI v2
- Terraform
- kubectl
- Helm
- rtfctl

### AWS permissions

Your AWS identity must be allowed to create and manage:

- VPC
- Subnets
- NAT Gateway
- Internet Gateway
- EKS cluster
- EKS managed node groups
- IAM roles and policies
- EC2 instances
- Elastic Load Balancers

Verify AWS access:

```bash
aws sts get-caller-identity
```

### MuleSoft prerequisites

You need:

- Anypoint Platform access
- Runtime Fabric entitlement
- Runtime Manager permission to create Runtime Fabric
- Runtime Fabric activation data
- MuleSoft enterprise license file, for example `license.lic`

---

## Step 1: Create Runtime Fabric in Anypoint Platform

Go to:

```text
Anypoint Platform
→ Runtime Manager
→ Runtime Fabrics
→ Create Runtime Fabric
```

Use values similar to:

```text
Runtime Fabric Name: mulesoft-eks-rtf
Deployment Target: Amazon Elastic Kubernetes Service
Installation Method: rtfctl
```

Copy the activation data.

Do not commit activation data to GitHub.

---

## Step 2: Configure Terraform Variables

Copy the example tfvars file:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region   = "ap-south-1"
cluster_name = "mulesoft-eks-cluster"

node_instance_types = ["t3.medium"]
desired_node_count  = 3
min_node_count      = 3
max_node_count      = 3

rtf_domain = "rtf.example.com"

install_runtime_fabric      = true
apply_rtf_ingress_template  = true
apply_mule_license          = true
mule_license_file           = "/absolute/path/to/license.lic"
```

Export Runtime Fabric activation data securely as an environment variable:

```bash
export TF_VAR_rtf_activation_data='<paste-activation-data-from-anypoint-platform>'
```

Optional: if you do not want Terraform to install Runtime Fabric yet:

```hcl
install_runtime_fabric = false
```

---

## Step 3: Run Terraform

From the repository root:

```bash
chmod +x scripts/terraform-apply.sh
./scripts/terraform-apply.sh
```

Or run manually:

```bash
cd terraform
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

---

## Step 4: Validate EKS

After Terraform completes:

```bash
aws eks update-kubeconfig \
  --region ap-south-1 \
  --name mulesoft-eks-cluster

kubectl get nodes -o wide
kubectl get pods -A
```

Expected result:

```text
3 worker nodes should be Ready.
NGINX Ingress Controller pods should be Running.
Runtime Fabric pods should be Running if install_runtime_fabric = true.
```

---

## Step 5: Validate NGINX Ingress

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

Capture the external hostname:

```bash
kubectl get svc ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Create wildcard DNS:

```text
*.rtf.example.com → <NGINX LoadBalancer DNS name>
```

---

## Step 6: Validate Runtime Fabric

```bash
kubectl get pods -n rtf
rtfctl status
rtfctl get mule-license
kubectl get ingress -n rtf
```

Also verify in Anypoint Platform:

```text
Runtime Manager
→ Runtime Fabrics
→ mulesoft-eks-rtf
→ Status should be Active
```

---

## Step 7: Associate Runtime Fabric with an Environment

In Anypoint Platform:

```text
Runtime Manager
→ Runtime Fabrics
→ mulesoft-eks-rtf
→ Associated Environments
→ Add Environment
→ Select Sandbox / Design / Production
→ Apply Allocations
```

After this, you can deploy Mule applications to the Runtime Fabric target.

---

## Destroy / Cleanup

Before destroying the infrastructure:

1. Delete Mule apps deployed to Runtime Fabric.
2. Delete API gateways deployed to Runtime Fabric.
3. Delete the Runtime Fabric record from Anypoint Runtime Manager.
4. Then run Terraform destroy.

```bash
chmod +x scripts/terraform-destroy.sh
./scripts/terraform-destroy.sh
```

Or run manually:

```bash
cd terraform
terraform destroy
```

The Terraform destroy path includes a best-effort `rtfctl uninstall` destroy provisioner when `install_runtime_fabric = true` and `uninstall_rtf_on_destroy = true`.

---

## Important Notes

### Runtime Fabric activation data

Activation data is sensitive. Do not hardcode it in `.tfvars` if this repository is pushed to GitHub. Use:

```bash
export TF_VAR_rtf_activation_data='<activation-data>'
```

### Mule license file

Use an absolute path:

```hcl
mule_license_file = "/Users/ashish/Downloads/license.lic"
```

### NGINX versus AWS Load Balancer Controller

This Terraform setup uses NGINX Ingress Controller by default.

You do not need AWS Load Balancer Controller for this lab setup. NGINX is exposed through a Kubernetes `Service` of type `LoadBalancer`, which causes AWS to provision a load balancer for the NGINX controller service.

Use AWS Load Balancer Controller only if you intentionally want AWS ALB/NLB-native ingress behavior.

---

## Cost Warning

This setup creates billable AWS resources, including:

- EKS control plane
- EC2 worker nodes
- NAT Gateway
- Load Balancer
- EBS volumes

Destroy the cluster after lab use:

```bash
cd terraform
terraform destroy
```
