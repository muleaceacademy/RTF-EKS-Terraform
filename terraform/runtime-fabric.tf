resource "terraform_data" "runtime_fabric_install" {
  count = var.install_runtime_fabric ? 1 : 0

  input = {
    cluster_name    = module.eks.cluster_name
    region          = var.aws_region
    install_trigger = var.rtf_install_trigger
  }

  # local-exec runs only when this resource is created. Keep replacement manual
  # through rtf_install_trigger or Terraform -replace so a normal code edit does
  # not reinstall a healthy Runtime Fabric.
  triggers_replace = [
    var.rtf_install_trigger,
    module.eks.cluster_name,
    module.eks.cluster_endpoint,
    var.kubernetes_version
  ]

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
      command -v helm >/dev/null 2>&1 || { echo "ERROR: Helm is not installed or not in PATH."; exit 1; }
      command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI is not installed or not in PATH."; exit 1; }

      # Use a dedicated temporary kubeconfig. AWS CLI otherwise merges into
      # ~/.kube/config, and concurrent local-exec provisioners can corrupt it.
      KUBECONFIG_FILE=$(mktemp "$${TMPDIR:-/tmp}/rtf-eks-kubeconfig.XXXXXX")
      trap 'rm -f "$KUBECONFIG_FILE"' EXIT
      export KUBECONFIG="$KUBECONFIG_FILE"
      chmod 600 "$KUBECONFIG_FILE"

      aws eks update-kubeconfig \
        --kubeconfig "$KUBECONFIG" \
        --region ${self.input.region} \
        --name ${self.input.cluster_name} >/dev/null

      kubectl get nodes

      echo "Checking Kubernetes server version before Runtime Fabric install..."

      SERVER_VERSION=$(kubectl get --raw='/version' \
        | tr -d '\n' \
        | sed -n -E 's/.*"gitVersion"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')

      if [ -z "$SERVER_VERSION" ]; then
        echo "ERROR: Unable to read Kubernetes server gitVersion from the /version endpoint."
        exit 1
      fi

      SERVER_MINOR=$(printf '%s' "$SERVER_VERSION" | sed -E 's/^v[0-9]+\.([0-9]+).*/\1/')

      if ! [[ "$SERVER_MINOR" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Unable to determine Kubernetes minor version from: $SERVER_VERSION"
        exit 1
      fi

      if [ "$SERVER_MINOR" -lt 31 ]; then
        echo "ERROR: Runtime Fabric chart requires Kubernetes >= 1.31, but this cluster is $SERVER_VERSION."
        echo "Fix: upgrade the cluster to a MuleSoft-supported Kubernetes version, then rerun Terraform."
        exit 1
      fi

      echo "Kubernetes server version check passed: $SERVER_VERSION"

      echo "Validating Kubernetes cluster for Runtime Fabric..."
      rtfctl validate "$RTF_ACTIVATION_DATA"

      # Do not reinstall a healthy existing Runtime Fabric on a retry.
      if kubectl get namespace rtf >/dev/null 2>&1 && helm status runtime-fabric -n rtf >/dev/null 2>&1; then
        echo "Existing Runtime Fabric Helm release detected. Skipping rtfctl install."
      else
        echo "Installing Runtime Fabric..."
        rtfctl install "$RTF_ACTIVATION_DATA"
      fi

      echo "Waiting for Runtime Fabric namespace..."
      RTF_NAMESPACE_FOUND=false
      for i in {1..60}; do
        if kubectl get namespace rtf >/dev/null 2>&1; then
          RTF_NAMESPACE_FOUND=true
          echo "rtf namespace found."
          break
        fi
        echo "Waiting for rtf namespace... attempt $i/60"
        sleep 10
      done

      if [ "$RTF_NAMESPACE_FOUND" != "true" ]; then
        echo "ERROR: Runtime Fabric installation did not create the rtf namespace."
        echo "Cluster namespaces:"
        kubectl get namespaces || true
        exit 1
      fi

      if ! helm status runtime-fabric -n rtf >/dev/null 2>&1; then
        echo "ERROR: Runtime Fabric Helm release was not found in the rtf namespace."
        kubectl get all -n rtf || true
        exit 1
      fi

      kubectl get pods -n rtf
      helm status runtime-fabric -n rtf
    EOT
  }

  depends_on = [
    terraform_data.update_kubeconfig,
    helm_release.ingress_nginx
  ]
}

# The Kubernetes provider's kubernetes_manifest resource can attempt to read the
# target cluster during planning. This local-exec step runs only after Runtime
# Fabric is installed and uses an isolated temporary kubeconfig.
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

  triggers_replace = [
    var.rtf_ingress_template_trigger,
    var.rtf_domain,
    var.enable_tls_in_rtf_template,
    var.rtf_tls_secret_name,
    terraform_data.runtime_fabric_install[0].id
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI is not installed or not in PATH."; exit 1; }
      command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl is not installed or not in PATH."; exit 1; }

      KUBECONFIG_FILE=$(mktemp "$${TMPDIR:-/tmp}/rtf-eks-kubeconfig.XXXXXX")
      trap 'rm -f "$KUBECONFIG_FILE"' EXIT
      export KUBECONFIG="$KUBECONFIG_FILE"
      chmod 600 "$KUBECONFIG_FILE"

      aws eks update-kubeconfig \
        --kubeconfig "$KUBECONFIG" \
        --region ${self.input.region} \
        --name ${self.input.cluster_name} >/dev/null

      if ! kubectl get namespace rtf >/dev/null 2>&1; then
        echo "ERROR: rtf namespace does not exist. Runtime Fabric must be installed successfully before applying the ingress template."
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

      KUBECONFIG_FILE=$(mktemp "$${TMPDIR:-/tmp}/rtf-eks-kubeconfig.XXXXXX")
      trap 'rm -f "$KUBECONFIG_FILE"' EXIT
      export KUBECONFIG="$KUBECONFIG_FILE"
      chmod 600 "$KUBECONFIG_FILE"

      aws eks update-kubeconfig \
        --kubeconfig "$KUBECONFIG" \
        --region ${self.input.region} \
        --name ${self.input.cluster_name} >/dev/null 2>&1 || exit 0

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

  # License application happens after the ingress template when it is enabled;
  # this removes competing local-exec processes during the RTF stage.
  triggers_replace = [
    var.mule_license_trigger,
    var.mule_license_file,
    var.apply_rtf_ingress_template ? terraform_data.rtf_nginx_ingress_template[0].id : terraform_data.runtime_fabric_install[0].id
  ]

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
      command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl is not installed or not in PATH."; exit 1; }
      command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI is not installed or not in PATH."; exit 1; }

      KUBECONFIG_FILE=$(mktemp "$${TMPDIR:-/tmp}/rtf-eks-kubeconfig.XXXXXX")
      trap 'rm -f "$KUBECONFIG_FILE"' EXIT
      export KUBECONFIG="$KUBECONFIG_FILE"
      chmod 600 "$KUBECONFIG_FILE"

      aws eks update-kubeconfig \
        --kubeconfig "$KUBECONFIG" \
        --region ${self.input.region} \
        --name ${self.input.cluster_name} >/dev/null

      if ! kubectl get namespace rtf >/dev/null 2>&1; then
        echo "ERROR: rtf namespace does not exist. Runtime Fabric must be installed successfully before applying the Mule license."
        exit 1
      fi

      rtfctl apply mule-license --file "${self.input.license_file}"
      rtfctl get mule-license
    EOT
  }

  depends_on = [terraform_data.rtf_nginx_ingress_template]
}
