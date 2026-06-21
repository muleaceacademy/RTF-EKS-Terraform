resource "terraform_data" "runtime_fabric_install" {
  count = var.install_runtime_fabric ? 1 : 0

  input = {
    cluster_name             = module.eks.cluster_name
    region                   = var.aws_region
    install_trigger          = var.rtf_install_trigger
    uninstall_rtf_on_destroy = var.uninstall_rtf_on_destroy
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      RTF_ACTIVATION_DATA = var.rtf_activation_data
    }
    command = <<-EOT
      set -euo pipefail

      if [ -z "$RTF_ACTIVATION_DATA" ]; then
        echo "ERROR: rtf_activation_data is empty. Export TF_VAR_rtf_activation_data before running terraform apply."
        exit 1
      fi

      command -v rtfctl >/dev/null 2>&1 || { echo "ERROR: rtfctl is not installed or not in PATH."; exit 1; }
      command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl is not installed or not in PATH."; exit 1; }
      command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI is not installed or not in PATH."; exit 1; }

      aws eks update-kubeconfig --region ${self.input.region} --name ${self.input.cluster_name}

      echo "Validating Kubernetes cluster for Runtime Fabric..."
      rtfctl validate "$RTF_ACTIVATION_DATA"

      echo "Installing Runtime Fabric..."
      rtfctl install "$RTF_ACTIVATION_DATA"

      echo "Runtime Fabric install command completed. Waiting for rtf namespace..."
      for i in {1..60}; do
        if kubectl get namespace rtf >/dev/null 2>&1; then
          echo "rtf namespace found."
          break
        fi
        echo "Waiting for rtf namespace... attempt $i/60"
        sleep 10
      done

      kubectl get pods -n rtf || true
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set +e

      if [ "${self.input.uninstall_rtf_on_destroy}" != "true" ]; then
        echo "Skipping rtfctl uninstall because uninstall_rtf_on_destroy=false."
        exit 0
      fi

      command -v aws >/dev/null 2>&1 || exit 0
      command -v rtfctl >/dev/null 2>&1 || exit 0

      echo "Best-effort Runtime Fabric uninstall. Delete Mule apps and Runtime Fabric record in Anypoint Runtime Manager first."
      aws eks update-kubeconfig --region ${self.input.region} --name ${self.input.cluster_name}
      rtfctl uninstall || true
    EOT
  }

  depends_on = [
    terraform_data.update_kubeconfig,
    helm_release.ingress_nginx
  ]
}

# The Kubernetes provider's kubernetes_manifest resource attempts to read the
# target cluster during planning. This local-exec approach applies the
# standard Kubernetes Ingress YAML only after EKS + NGINX + RTF are ready.
resource "terraform_data" "rtf_nginx_ingress_template" {
  count = var.install_runtime_fabric && var.apply_rtf_ingress_template ? 1 : 0

  input = {
    cluster_name    = module.eks.cluster_name
    region          = var.aws_region
    manifest_file   = abspath("${path.module}/../manifests/rtf-nginx-ingress-template.yaml")
    template_host   = local.rtf_template_host
    rtf_domain      = var.rtf_domain
    enable_tls      = var.enable_tls_in_rtf_template
    tls_secret_name = var.rtf_tls_secret_name
    trigger         = var.rtf_ingress_template_trigger
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI is not installed or not in PATH."; exit 1; }
      command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl is not installed or not in PATH."; exit 1; }

      aws eks update-kubeconfig --region ${self.input.region} --name ${self.input.cluster_name}

      if ! kubectl get namespace rtf >/dev/null 2>&1; then
        echo "ERROR: rtf namespace does not exist. Runtime Fabric must be installed before applying the ingress template."
        exit 1
      fi

      mkdir -p "$(dirname "${self.input.manifest_file}")"

      TLS_BLOCK=""
      if [ "${self.input.enable_tls}" = "true" ]; then
        TLS_BLOCK=$(cat <<YAML
  tls:
    - hosts:
        - "*.${self.input.rtf_domain}"
      secretName: ${self.input.tls_secret_name}
YAML
)
      fi

      cat > "${self.input.manifest_file}" <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rtf-nginx-ingress-template
  namespace: rtf
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-body-size: "20m"
spec:
  ingressClassName: rtf-nginx
$${TLS_BLOCK}
  rules:
    - host: ${self.input.template_host}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: service-name
                port:
                  name: service-port
YAML

      echo "Generated Runtime Fabric ingress template: ${self.input.manifest_file}"
      kubectl apply -f "${self.input.manifest_file}"
      kubectl get ingress rtf-nginx-ingress-template -n rtf
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set +e
      command -v aws >/dev/null 2>&1 || exit 0
      command -v kubectl >/dev/null 2>&1 || exit 0
      aws eks update-kubeconfig --region ${self.input.region} --name ${self.input.cluster_name}
      kubectl delete ingress rtf-nginx-ingress-template -n rtf --ignore-not-found=true
    EOT
  }

  depends_on = [terraform_data.runtime_fabric_install]
}

resource "terraform_data" "mule_license" {
  count = var.install_runtime_fabric && var.apply_mule_license ? 1 : 0

  input = {
    cluster_name = module.eks.cluster_name
    region       = var.aws_region
    license_file = var.mule_license_file
    trigger      = var.mule_license_trigger
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      if [ -z "${self.input.license_file}" ]; then
        echo "ERROR: mule_license_file is empty."
        exit 1
      fi

      if [ ! -f "${self.input.license_file}" ]; then
        echo "ERROR: Mule license file does not exist: ${self.input.license_file}"
        exit 1
      fi

      command -v rtfctl >/dev/null 2>&1 || { echo "ERROR: rtfctl is not installed or not in PATH."; exit 1; }
      aws eks update-kubeconfig --region ${self.input.region} --name ${self.input.cluster_name}

      rtfctl apply mule-license --file "${self.input.license_file}"
      rtfctl get mule-license
    EOT
  }

  depends_on = [terraform_data.runtime_fabric_install]
}
