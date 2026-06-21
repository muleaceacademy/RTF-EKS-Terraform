# Architecture: MuleSoft Runtime Fabric on AWS EKS using Terraform

## Overview

This solution provisions a MuleSoft Runtime Fabric foundation on Amazon EKS using Terraform.

The architecture is split into four layers:

1. AWS network layer
2. AWS EKS compute layer
3. Kubernetes ingress layer
4. MuleSoft Runtime Fabric layer

## AWS Network Layer

Terraform creates a dedicated VPC with:

- Public subnets
- Private subnets
- Internet Gateway
- NAT Gateway
- DNS hostnames enabled
- DNS support enabled

Worker nodes are deployed into private subnets.

## EKS Compute Layer

Terraform creates:

- EKS control plane
- EKS managed node group
- 3 EC2 worker nodes by default
- IAM roles required by EKS and nodes

Default lab sizing:

```text
Instance type: t3.medium
Desired nodes: 3
Minimum nodes: 3
Maximum nodes: 3
Disk size: 50 GB
```

For production, validate sizing against expected Mule app workloads.

## Kubernetes Ingress Layer

Terraform installs NGINX Ingress Controller using the Terraform Helm provider.

The NGINX controller is exposed using a Kubernetes `Service` of type `LoadBalancer`.

AWS provisions an external load balancer for that service.

## Runtime Fabric Layer

Runtime Fabric is installed using `rtfctl` through a Terraform `local-exec` orchestration step.

## DNS Pattern

Recommended DNS pattern:

```text
*.rtf.example.com -> NGINX LoadBalancer DNS name
```

Example Mule app endpoint:

```text
https://orders-api.rtf.example.com
```
