# Troubleshooting

## Error: reading EKS Cluster couldn't find resource

Cause: The earlier Terraform code tried to read the EKS cluster using a data source before the cluster existed.

Fix: Use the fixed `providers.tf` from this repository which removes data sources and configures Kubernetes/Helm providers from `module.eks` outputs using AWS CLI token authentication.

## Terraform provider cannot connect to EKS

Run:
```bash
aws sts get-caller-identity
aws eks update-kubeconfig --region ap-south-1 --name mulesoft-eks-cluster
kubectl get nodes
```

## rtfctl not found

Install prerequisites:
```bash
./scripts/install-prerequisites-mac.sh
```

## rtfctl validate fails

Common causes: Kubernetes context points to wrong cluster, nodes not Ready, invalid activation data, ingress controller not installed.

Check:
```bash
kubectl config current-context
kubectl get nodes
kubectl get pods -A
kubectl get pods -n ingress-nginx
```

## NGINX LoadBalancer external hostname is pending

Check:
```bash
kubectl get svc -n ingress-nginx
kubectl describe svc ingress-nginx-controller -n ingress-nginx
```

Common causes: AWS IAM permissions missing, subnets not tagged correctly, load balancer quota reached.

## Runtime Fabric namespace not found

If `kubectl get pods -n rtf` fails, Runtime Fabric install did not complete. Rerun manually:
```bash
rtfctl validate "$TF_VAR_rtf_activation_data"
rtfctl install "$TF_VAR_rtf_activation_data"
```

## Terraform destroy fails because of load balancer resources

Delete remaining app ingress/service resources before destroying the cluster:
```bash
kubectl get svc -A | grep LoadBalancer
kubectl get ingress -A
```
