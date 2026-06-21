# Terraform Design Notes

## First-Apply Provider Fix

The Terraform configuration intentionally does not use `data.aws_eks_cluster` to configure the Kubernetes and Helm providers.

Reason: on the first `terraform apply`, the EKS cluster does not exist yet. A data source read can happen during planning, causing the error: `Error: reading EKS Cluster: couldn't find resource`.

Instead, the providers are configured directly from `module.eks` outputs.

Authentication uses AWS CLI exec with `client.authentication.k8s.io/v1beta1`.

The Runtime Fabric ingress template is applied through `kubectl apply` after Runtime Fabric installation to avoid planning-time Kubernetes API lookups.

## Why Terraform plus rtfctl?

Terraform provisions AWS infrastructure and installs Helm charts. Runtime Fabric installation requires activation data from Anypoint Runtime Manager. This repository orchestrates `rtfctl validate`, `rtfctl install`, and `rtfctl apply mule-license` from the local machine.

## Why terraform_data instead of null_resource?

The repository uses `terraform_data` for local execution orchestration. It is preferred over older `null_resource` patterns in newer Terraform versions.

## Sensitive Data Handling

Runtime Fabric activation data should be passed as an environment variable:

```bash
export TF_VAR_rtf_activation_data='<activation-data>'
```

Do not commit activation data to GitHub.

## Re-running Runtime Fabric Install

Change `rtf_install_trigger` value to trigger the local-exec again.

## Destroy Behavior

Terraform destroy includes a best-effort `rtfctl uninstall` if `uninstall_rtf_on_destroy = true`. Before destroy, delete Mule apps, API gateways, and the Runtime Fabric record from Anypoint Runtime Manager.
