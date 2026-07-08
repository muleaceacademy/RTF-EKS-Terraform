# MuleSoft Runtime Fabric on AWS EKS using Terraform

This repository provisions an AWS EKS cluster and installs the Kubernetes foundation required for MuleSoft Runtime Fabric using Terraform.


## YouTube Tutorial
Watch the complete walkthrough here:

<a href="https://www.youtube.com/watch?v=WMDKV3wshu0" target="_blank" rel="noopener noreferrer">
  <img 
    src="https://img.youtube.com/vi/WMDKV3wshu0/maxresdefault.jpg" 
    alt="Watch the YouTube video" 
    width="720"
  />
</a>

---

The implementation is intentionally divided into three operational phases:

1. **Part 1 — Create AWS infrastructure**
2. **Part 2 — Install and validate MuleSoft Runtime Fabric**
3. **Part 3 — Safely uninstall and destroy all resources**

> **Important:** Terraform provisions AWS and Kubernetes infrastructure. Runtime Fabric activation data must still be generated from Anypoint Platform Runtime Manager. Terraform passes this activation data to `rtfctl`, which executes Runtime Fabric validation and installation from your local machine.

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
│   ├── install-prerequisites-windows.ps1
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

## Simplified Terraform Flow

```text
terraform.tfvars
   ↓
variables.tf
   ↓
locals.tf
   ↓
main.tf
   ├── VPC Module
   └── EKS Module
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

For learning purposes, the Terraform implementation can be understood primarily through these files:

```text
main.tf
variables.tf
outputs.tf
```

Terraform modules are reusable collections of related AWS resources. They help avoid manually creating hundreds of individual resources.

```text
Root Terraform Module
│
├── VPC Module
│   ├── VPC
│   ├── Public and private subnets
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

---

# Part 1 — Create AWS Resources

This phase creates the AWS networking, EKS cluster, worker nodes, and NGINX Ingress Controller.

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
        +-- Managed Node Group: 3 worker nodes
        |
        +-- NGINX Ingress Controller
              +-- AWS Load Balancer
```

## Prerequisites

### Install local tools on Mac

Run:
If Mac:
```bash
chmod +x scripts/install-prerequisites-mac.sh
./scripts/install-prerequisites-mac.sh
```
If Windows:
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Unblock-File .\install-prerequisites-windows.ps1
.\install-prerequisites-windows.ps1
```
The script installs or validates:

* Homebrew
* AWS CLI v2
* Terraform
* kubectl
* Helm
* rtfctl
* eksctl

Verify installations:

```bash
aws --version
terraform --version
kubectl version --client
helm version
rtfctl --help
```

### Verify AWS Credentials

Your AWS identity must be permitted to create and manage:

* VPC
* Subnets
* NAT Gateway
* Internet Gateway
* EKS cluster
* EKS managed node groups
* IAM roles and policies
* EC2 instances
* Elastic Load Balancers
* Security groups
* EBS volumes

Verify the authenticated AWS identity:

```bash
aws sts get-caller-identity
```

Expected output should show your AWS Account ID, IAM user, or assumed role.

---

## Configure Terraform Variables

Copy the sample variable file:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Update `terraform.tfvars`:

```hcl
aws_region   = "ap-south-1"
cluster_name = "mulesoft-eks-cluster"

node_instance_types = ["t3.medium"]

desired_node_count = 3
min_node_count     = 3
max_node_count     = 3

rtf_domain = "rtf.muleaceacademy.com"

# Disable Runtime Fabric installation during Part 1.
install_runtime_fabric     = false
apply_rtf_ingress_template = false
apply_mule_license         = false
```

> Set `install_runtime_fabric = false` during this phase. Runtime Fabric installation will be enabled in Part 2 after the EKS cluster is validated.

---

## Initialize and Provision AWS Infrastructure

Run the following commands from the `terraform` directory:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Or run the helper script from the repository root:

```bash
chmod +x scripts/terraform-apply.sh
./scripts/terraform-apply.sh
```

Terraform creates:

* VPC
* Public and private subnets
* NAT Gateway
* Route tables
* Internet Gateway
* EKS control plane
* EKS managed node group with three worker nodes
* IAM roles and policies
* Security groups
* NGINX Ingress Controller through Helm
* AWS Load Balancer for the NGINX Controller service

---

## Verify AWS and EKS Resources

Update your local Kubernetes configuration:

```bash
aws eks update-kubeconfig \
  --region ap-south-1 \
  --name mulesoft-eks-cluster
```

Verify the EKS cluster:

```bash
aws eks describe-cluster \
  --region ap-south-1 \
  --name mulesoft-eks-cluster \
  --query "cluster.status" \
  --output text
```

Expected output:

```text
ACTIVE
```

Verify Kubernetes worker nodes:

```bash
kubectl get nodes -o wide
```

Expected result:

```text
3 worker nodes should be in Ready status.
```

Verify system pods:

```bash
kubectl get pods -A
```

Verify NGINX Ingress Controller:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

Expected result:

```text
NGINX controller pods should be Running.
The ingress-nginx-controller service should have an external AWS Load Balancer hostname.
```

Get the NGINX Load Balancer hostname:

```bash
kubectl get svc ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Save this hostname because it is required for your DNS configuration in Part 2.

---

# Part 2 — Install MuleSoft Runtime Fabric, Ingress Template, and Mule License

This phase installs Runtime Fabric on the EKS cluster, applies the Runtime Fabric NGINX ingress template, and applies the Mule enterprise license.

## MuleSoft Prerequisites

You need:

* Anypoint Platform access
* Runtime Fabric entitlement
* Runtime Manager permission to create Runtime Fabrics
* Runtime Fabric activation data
* MuleSoft enterprise license file, for example `license.lic`

---

## Create Runtime Fabric in Anypoint Platform

Navigate to:

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

Copy the Runtime Fabric activation data.

> Do not commit activation data to GitHub or store it in `terraform.tfvars`.

Export activation data as an environment variable:

```bash
export TF_VAR_rtf_activation_data='<paste-activation-data-from-anypoint-platform>'
```

Verify that the variable is available:

```bash
echo $TF_VAR_rtf_activation_data
```

Do not share the output in screenshots, logs, GitHub commits, or documentation.

---

## Configure Runtime Fabric Variables

Update `terraform/terraform.tfvars`:

```hcl
aws_region   = "ap-south-1"
cluster_name = "mulesoft-eks-cluster"

node_instance_types = ["t3.medium"]

desired_node_count = 3
min_node_count     = 3
max_node_count     = 3

rtf_domain = "rtf.muleaceacademy.com"

install_runtime_fabric     = true
apply_rtf_ingress_template = true
apply_mule_license         = true

mule_license_file = "/absolute/path/to/license.lic"
```

Example:

```hcl
mule_license_file = "/Users/ashish/Downloads/license.lic"
```

---

## Configure Wildcard DNS

Get the NGINX Load Balancer hostname:

```bash
kubectl get svc ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Create a wildcard DNS record:

```text
*.rtf.muleaceacademy.com → <NGINX Load Balancer DNS Name>
```

Example:

```text
*.rtf.muleaceacademy.com → a1234567890.ap-south-1.elb.amazonaws.com
```

This wildcard DNS record allows Runtime Fabric applications to receive inbound traffic through NGINX.

---

## Install Runtime Fabric

Run Terraform again after enabling Runtime Fabric variables:

```bash
cd terraform

terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Terraform performs the following tasks:

```text
1. Validates the Kubernetes cluster configuration using rtfctl.
2. Installs MuleSoft Runtime Fabric into the EKS cluster.
3. Creates the Runtime Fabric namespace and supporting components.
4. Applies the Runtime Fabric NGINX ingress template.
5. Applies the MuleSoft enterprise license file.
```

The `runtime-fabric.tf` file uses Terraform `local-exec` provisioners to run commands similar to:

```bash
rtfctl validate
rtfctl install
rtfctl apply mule-license
kubectl apply -f manifests/rtf-nginx-ingress-template.yaml
```

---

## Verify Runtime Fabric Installation

Verify the Runtime Fabric namespace:

```bash
kubectl get namespaces
```

Expected result:

```text
rtf namespace should exist.
```

Verify Runtime Fabric pods:

```bash
kubectl get pods -n rtf
```

Expected result:

```text
Runtime Fabric pods should be Running or Completed where applicable.
```

View detailed pod status:

```bash
kubectl get pods -n rtf -o wide
```

Check Runtime Fabric events:

```bash
kubectl get events -n rtf --sort-by='.lastTimestamp'
```

Verify Runtime Fabric status:

```bash
rtfctl status
```

Verify that the Mule license was applied:

```bash
rtfctl get mule-license
```

Verify Runtime Fabric ingress resources:

```bash
kubectl get ingress -n rtf
```

Verify NGINX ingress resources:

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

---

## Validate Runtime Fabric in Anypoint Platform

Navigate to:

```text
Runtime Manager
→ Runtime Fabrics
→ mulesoft-eks-rtf
```

Expected status:

```text
Active
```

---

## Associate Runtime Fabric with an Environment

In Anypoint Platform:

```text
Runtime Manager
→ Runtime Fabrics
→ mulesoft-eks-rtf
→ Associated Environments
→ Add Environment
→ Select Sandbox, Design, or Production
→ Apply Allocations
```

After associating the environment, you can deploy Mule applications to Runtime Fabric.

---

## Traffic Flow After Mule Application Deployment

```text
Client
  ↓
Wildcard DNS Record
  ↓
AWS Load Balancer
  ↓
NGINX Ingress Controller
  ↓
Runtime Fabric Generated Ingress
  ↓
Mule Application Service
  ↓
Mule Application Pod
```

---

# Part 3 — Uninstall Runtime Fabric and Destroy Everything

Use this phase only after all Mule applications, APIs, and Runtime Fabric dependencies have been removed.

> **Warning:** Terraform destroy removes AWS infrastructure including the EKS cluster, worker nodes, VPC resources, NAT Gateway, load balancer, and associated EBS volumes.

---

## Pre-Destroy Checklist

Before running Terraform destroy:

1. Delete Mule applications deployed to Runtime Fabric.
2. Delete API gateways deployed to Runtime Fabric.
3. Verify that no critical traffic is routed through the Runtime Fabric domain.
4. Remove the Runtime Fabric association from Anypoint Platform environments.
5. Delete the Runtime Fabric record from Anypoint Runtime Manager.
6. Confirm that no applications, APIs, or integrations still depend on the EKS cluster.

Verify deployed applications are removed:

```bash
kubectl get pods -n rtf
kubectl get ingress -n rtf
kubectl get svc -n rtf
```

Verify no Kubernetes workloads remain outside system namespaces:

```bash
kubectl get pods -A
```

---

## Uninstall Runtime Fabric

If enabled, the Terraform destroy workflow runs a best-effort Runtime Fabric uninstall.

Ensure these Terraform variables are configured:

```hcl
install_runtime_fabric   = true
uninstall_rtf_on_destroy = true
```

Run the destroy script from the repository root:

```bash
chmod +x scripts/terraform-destroy.sh
./scripts/terraform-destroy.sh
```

Or run manually:

```bash
cd terraform
terraform destroy
```

Terraform performs the following activities:

```text
1. Attempts to uninstall Runtime Fabric using rtfctl.
2. Removes Runtime Fabric Kubernetes resources.
3. Removes the NGINX Ingress Controller.
4. Deletes the AWS Load Balancer created for NGINX.
5. Deletes EKS worker nodes.
6. Deletes the EKS cluster.
7. Deletes VPC networking resources, including NAT Gateway and subnets.
```

---

## Verify Runtime Fabric Removal

Before the EKS cluster is deleted, verify that Runtime Fabric resources are removed:

```bash
kubectl get namespace rtf
```

Expected result:

```text
Error from server (NotFound): namespaces "rtf" not found
```

Verify NGINX ingress resources are removed:

```bash
kubectl get namespace ingress-nginx
```

Expected result:

```text
Error from server (NotFound): namespaces "ingress-nginx" not found
```

---

## Verify AWS Infrastructure Removal

After Terraform destroy completes, verify the EKS cluster no longer exists:

```bash
aws eks describe-cluster \
  --region ap-south-1 \
  --name mulesoft-eks-cluster
```

Expected result:

```text
ResourceNotFoundException
```

Verify that worker node instances are terminated:

```bash
aws ec2 describe-instances \
  --region ap-south-1 \
  --filters "Name=tag:Name,Values=mulesoft-eks-cluster*"
```

Verify that load balancers are removed:

```bash
aws elbv2 describe-load-balancers \
  --region ap-south-1
```

Verify NAT Gateway deletion:

```bash
aws ec2 describe-nat-gateways \
  --region ap-south-1
```

---

## Important Security Notes

### Runtime Fabric Activation Data

Do not store activation data in:

```text
terraform.tfvars
GitHub repositories
Screenshots
Terraform state backups
Public CI/CD logs
```

Use an environment variable:

```bash
export TF_VAR_rtf_activation_data='<activation-data>'
```

### Mule License File

Use an absolute file path:

```hcl
mule_license_file = "/Users/ashish/Downloads/license.lic"
```

Do not commit the Mule license file into source control.

---

## NGINX Ingress Controller Versus AWS Load Balancer Controller

This repository uses the NGINX Ingress Controller.

```text
Kubernetes Service Type LoadBalancer
        ↓
AWS creates a Load Balancer
        ↓
AWS Load Balancer forwards traffic to NGINX
        ↓
NGINX routes traffic to Runtime Fabric applications
```

You do not need AWS Load Balancer Controller for this lab implementation.

Use AWS Load Balancer Controller only when you intentionally require AWS ALB or NLB native ingress patterns.

---

## Cost Warning

This implementation creates billable AWS services:

* EKS control plane
* EC2 worker nodes
* NAT Gateway
* Elastic Load Balancer
* EBS volumes
* Data transfer charges

Destroy the infrastructure after completing your lab or demonstration:

```bash
cd terraform
terraform destroy
```
