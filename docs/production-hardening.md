# Production Hardening Guide

This Terraform repository is suitable as a lab or starting template. For production, apply the hardening practices below.

## EKS Sizing

Avoid default lab sizing for production. Review number of Mule applications, worker replica count, API traffic volume, payload size, CPU and memory profile, and logging and monitoring overhead.

## Networking

Recommended production setup:

- Private EKS endpoint if possible
- Restricted public endpoint CIDR if public endpoint is required
- Private worker nodes
- VPC flow logs
- Separate VPC/subnet strategy per environment
- Controlled egress through NAT or firewall appliance

## Security

Recommended controls:

- Least privilege IAM
- AWS IAM Identity Center or role-based access
- Kubernetes RBAC
- Secrets externalization
- TLS for ingress
- WAF if using ALB-based ingress
- Restricted security groups
- Image scanning
- Audit logs

## Ingress

For production, decide between NGINX Ingress Controller, AWS Load Balancer Controller with ALB, or NGINX behind NLB. Use TLS certificates and wildcard DNS.

## Observability

Add CloudWatch Container Insights, Prometheus/Grafana, centralized logging, alerting for pod restarts, node pressure, CPU, memory, and disk, and Mule application-level monitoring in Anypoint Monitoring.

## Terraform State

For team use, store state remotely using S3 backend with DynamoDB state locking, versioning enabled, and encryption enabled.
