#!/bin/bash

# NVIDIA GPU Operator Installation Script for OpenShift
# This script automates the installation of the NVIDIA GPU Operator

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="nvidia-gpu-operator"
OPERATOR_GROUP_NAME="nvidia-gpu-operator-group"
SUBSCRIPTION_NAME="gpu-operator-certified"
PACKAGE_MANIFEST="gpu-operator-certified"

# NFD Configuration
NFD_NAMESPACE="openshift-nfd"
NFD_OPERATOR_GROUP_NAME="openshift-nfd"
NFD_SUBSCRIPTION_NAME="nfd"
NFD_PACKAGE_MANIFEST="nfd"
NFD_CR_NAME="nfd-instance"

# cert-manager Configuration
CERTMANAGER_NAMESPACE="cert-manager-operator"
CERTMANAGER_OPERATOR_GROUP_NAME="cert-manager-operator-group"
CERTMANAGER_SUBSCRIPTION_NAME="openshift-cert-manager-operator"
CERTMANAGER_PACKAGE_MANIFEST="openshift-cert-manager-operator"

# MinIO Configuration
MINIO_NAMESPACE="minio"

# OpenShift AI Configuration
RHOAI_OPERATOR_NAMESPACE="redhat-ods-operator"
RHOAI_APPLICATIONS_NAMESPACE="redhat-ods-applications"
RHOAI_NOTEBOOKS_NAMESPACE="rhods-notebooks"
RHOAI_OPERATOR_GROUP_NAME="redhat-ods-operator-group"
RHOAI_SUBSCRIPTION_NAME="rhods-operator"
RHOAI_PACKAGE_MANIFEST="rhods-operator"

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if oc is installed and configured
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v oc &> /dev/null; then
        print_error "OpenShift CLI (oc) is not installed. Please install it first."
        exit 1
    fi
    
    if ! oc whoami &> /dev/null; then
        print_error "Not logged in to OpenShift cluster. Please run 'oc login' first."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install jq first (required for parsing JSON)."
        exit 1
    fi
    
    print_info "Logged in as: $(oc whoami)"
    print_info "Connected to cluster: $(oc cluster-info | head -n1)"
}

# Function to create namespace
create_namespace() {
    print_info "Creating namespace: ${NAMESPACE}"
    
    if oc get namespace "${NAMESPACE}" &> /dev/null; then
        print_warn "Namespace ${NAMESPACE} already exists. Skipping creation."
        return
    fi
    
    # Get script directory to find the YAML file
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local namespace_file="${script_dir}/nvidia-operator/namespace.yaml"
    
    if [ ! -f "${namespace_file}" ]; then
        print_error "Namespace YAML file not found: ${namespace_file}"
        exit 1
    fi
    
    oc create -f "${namespace_file}"
    print_info "Namespace ${NAMESPACE} created successfully"
}

# Function to enable namespace monitoring (optional, but recommended)
enable_namespace_monitoring() {
    print_info "Enabling namespace monitoring for Prometheus..."
    oc label ns/${NAMESPACE} openshift.io/cluster-monitoring=true --overwrite
    print_info "Namespace monitoring enabled"
}

# Function to check for multiple OperatorGroups in namespace
check_multiple_operatorgroups() {
    local namespace=$1
    local expected_og=$2
    
    local og_count
    og_count=$(oc get operatorgroup -n "${namespace}" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "${og_count}" -gt 1 ]; then
        print_error "Multiple OperatorGroups found in namespace ${namespace}!"
        print_error "This will cause CSV installation to fail with: 'csv created in namespace with multiple operatorgroups, can't pick one automatically'"
        echo ""
        print_info "Existing OperatorGroups:"
        oc get operatorgroup -n "${namespace}" 2>/dev/null || true
        echo ""
        print_error "Please delete the extra OperatorGroup(s) or use a different namespace."
        print_info "To list OperatorGroups: oc get operatorgroup -n ${namespace}"
        print_info "To delete an OperatorGroup: oc delete operatorgroup <name> -n ${namespace}"
        return 1
    elif [ "${og_count}" -eq 1 ]; then
        local existing_og
        existing_og=$(oc get operatorgroup -n "${namespace}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ "${existing_og}" != "${expected_og}" ]; then
            print_warn "Found different OperatorGroup '${existing_og}' in namespace ${namespace}"
            print_warn "Expected: ${expected_og}"
            print_warn "This may cause issues. Consider deleting it and letting the script create the correct one."
        fi
    fi
    
    return 0
}

# Function to create OperatorGroup
create_operator_group() {
    print_info "Creating OperatorGroup: ${OPERATOR_GROUP_NAME}"
    
    # Check for multiple OperatorGroups before creating
    if ! check_multiple_operatorgroups "${NAMESPACE}" "${OPERATOR_GROUP_NAME}"; then
        exit 1
    fi
    
    if oc get operatorgroup "${OPERATOR_GROUP_NAME}" -n "${NAMESPACE}" &> /dev/null; then
        print_warn "OperatorGroup ${OPERATOR_GROUP_NAME} already exists. Skipping creation."
        return
    fi
    
    # Get script directory to find the YAML file
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local og_file="${script_dir}/nvidia-operator/operatorgroup.yaml"
    
    if [ ! -f "${og_file}" ]; then
        print_error "OperatorGroup YAML file not found: ${og_file}"
        exit 1
    fi
    
    oc create -f "${og_file}"
    print_info "OperatorGroup ${OPERATOR_GROUP_NAME} created successfully"
}

# Function to get channel from packagemanifest
get_channel() {
    print_info "Getting default channel from packagemanifest..." >&2
    
    local channel
    channel=$(oc get packagemanifest "${PACKAGE_MANIFEST}" -n openshift-marketplace -o jsonpath='{.status.defaultChannel}' 2>/dev/null)
    
    if [ -z "${channel}" ]; then
        print_error "Failed to get channel from packagemanifest ${PACKAGE_MANIFEST}" >&2
        print_error "Make sure the packagemanifest exists in openshift-marketplace namespace" >&2
        exit 1
    fi
    
    print_info "Found channel: ${channel}" >&2
    echo "${channel}"
}

# Function to get startingCSV from packagemanifest
get_starting_csv() {
    local channel=$1
    print_info "Getting startingCSV for channel: ${channel}" >&2
    
    local starting_csv
    local json_output
    json_output=$(oc get packagemanifests/"${PACKAGE_MANIFEST}" -n openshift-marketplace -ojson 2>/dev/null)
    
    if [ -z "${json_output}" ]; then
        print_error "Failed to get packagemanifest ${PACKAGE_MANIFEST}" >&2
        exit 1
    fi
    
    starting_csv=$(echo "${json_output}" | jq -r --arg ch "${channel}" '.status.channels[] | select(.name == $ch) | .currentCSV' 2>/dev/null)
    
    if [ -z "${starting_csv}" ] || [ "${starting_csv}" == "null" ]; then
        print_error "Failed to get startingCSV for channel ${channel}" >&2
        print_error "Available channels:" >&2
        echo "${json_output}" | jq -r '.status.channels[].name' 2>/dev/null || true >&2
        exit 1
    fi
    
    print_info "Found startingCSV: ${starting_csv}" >&2
    echo "${starting_csv}"
}

# Function to create Subscription
create_subscription() {
    print_info "Creating Subscription: ${SUBSCRIPTION_NAME}"
    
    if oc get subscription "${SUBSCRIPTION_NAME}" -n "${NAMESPACE}" &> /dev/null; then
        print_warn "Subscription ${SUBSCRIPTION_NAME} already exists. Skipping creation."
        return
    fi
    
    # Get channel and startingCSV dynamically
    local channel
    channel=$(get_channel)
    
    local starting_csv
    starting_csv=$(get_starting_csv "${channel}")
    
    # Get script directory to save subscription file
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local subscription_dir="${script_dir}/nvidia-operator"
    local subscription_file="${subscription_dir}/subscription.yaml"
    
    # Ensure directory exists
    if [ ! -d "${subscription_dir}" ]; then
        print_error "Directory ${subscription_dir} does not exist!"
        exit 1
    fi
    
    print_info "Creating subscription YAML file: ${subscription_file}"
    
    cat <<EOF > "${subscription_file}"
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${SUBSCRIPTION_NAME}
  namespace: ${NAMESPACE}
spec:
  channel: ${channel}
  installPlanApproval: Manual
  name: ${PACKAGE_MANIFEST}
  source: certified-operators
  sourceNamespace: openshift-marketplace
  startingCSV: ${starting_csv}
EOF
    
    # Create the subscription
    oc create -f "${subscription_file}"
    
    print_info "Subscription ${SUBSCRIPTION_NAME} created successfully"
    print_info "Subscription YAML saved to: ${subscription_file}"
}

# Function to automatically approve InstallPlan
approve_installplan() {
    local namespace=$1
    local operator_name=$2
    
    print_info "Waiting for InstallPlan to be created for ${operator_name}..."
    
    local max_attempts=30
    local attempt=0
    local installplan=""
    
    # Wait for InstallPlan to be created
    while [ $attempt -lt $max_attempts ]; do
        installplan=$(oc get installplan -n "${namespace}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [ -n "${installplan}" ]; then
            break
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done
    
    echo ""
    
    if [ -z "${installplan}" ]; then
        print_warn "No InstallPlan found after waiting. It may be created later."
        print_info "You can check with: oc get installplan -n ${namespace}"
        return 1
    fi
    
    print_info "Found InstallPlan: ${installplan}"
    
    # Check if already approved
    local approved
    approved=$(oc get installplan "${installplan}" -n "${namespace}" -o jsonpath='{.spec.approved}' 2>/dev/null || echo "false")
    
    if [ "${approved}" == "true" ]; then
        print_info "InstallPlan ${installplan} is already approved!"
        return 0
    fi
    
    # Automatically approve the InstallPlan
    print_info "Approving InstallPlan ${installplan}..."
    if oc patch installplan "${installplan}" -n "${namespace}" --type merge -p '{"spec":{"approved":true}}' 2>/dev/null; then
        print_info "InstallPlan ${installplan} approved successfully!"
        return 0
    else
        print_error "Failed to approve InstallPlan ${installplan}"
        return 1
    fi
}

# Function to wait for operator installation
wait_for_operator() {
    print_info "Waiting for NVIDIA GPU Operator to be installed..."
    print_info "This may take a few minutes..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if oc get csv -n "${NAMESPACE}" -o jsonpath='{.items[*].status.phase}' | grep -q "Succeeded"; then
            print_info "NVIDIA GPU Operator installed successfully!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 10
    done
    
    echo ""
    print_warn "Operator installation is taking longer than expected."
    print_info "You can check the status manually with:"
    print_info "  oc get csv -n ${NAMESPACE}"
    print_info "  oc get pods -n ${NAMESPACE}"
}

# Function to create NFD namespace
create_nfd_namespace() {
    print_info "Creating NFD namespace: ${NFD_NAMESPACE}"
    
    if oc get namespace "${NFD_NAMESPACE}" &> /dev/null; then
        print_warn "Namespace ${NFD_NAMESPACE} already exists. Skipping creation."
        return
    fi
    
    # Get script directory to find the YAML file
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local namespace_file="${script_dir}/nfd-operator/namespace.yaml"
    
    if [ ! -f "${namespace_file}" ]; then
        print_error "NFD namespace YAML file not found: ${namespace_file}"
        exit 1
    fi
    
    oc apply -f "${namespace_file}"
    print_info "Namespace ${NFD_NAMESPACE} created successfully"
}

# Function to apply NFD OperatorGroup
apply_nfd_operator_group() {
    print_info "Applying NFD OperatorGroup..."
    
    # Get script directory to find the YAML file
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local og_file="${script_dir}/nfd-operator/operatorgroup.yaml"
    
    if [ ! -f "${og_file}" ]; then
        print_error "NFD OperatorGroup YAML file not found: ${og_file}"
        exit 1
    fi
    
    oc apply -f "${og_file}"
    print_info "NFD OperatorGroup applied successfully"
}

# Function to get NFD channel from packagemanifest
get_nfd_channel() {
    print_info "Getting default channel from NFD packagemanifest..." >&2
    
    local channel
    channel=$(oc get packagemanifest "${NFD_PACKAGE_MANIFEST}" -n openshift-marketplace -o jsonpath='{.status.defaultChannel}' 2>/dev/null)
    
    if [ -z "${channel}" ]; then
        print_error "Failed to get channel from packagemanifest ${NFD_PACKAGE_MANIFEST}" >&2
        print_error "Make sure the packagemanifest exists in openshift-marketplace namespace" >&2
        exit 1
    fi
    
    print_info "Found NFD channel: ${channel}" >&2
    echo "${channel}"
}

# Function to get NFD startingCSV from packagemanifest
get_nfd_starting_csv() {
    local channel=$1
    print_info "Getting startingCSV for NFD channel: ${channel}" >&2
    
    local starting_csv
    local json_output
    json_output=$(oc get packagemanifests/"${NFD_PACKAGE_MANIFEST}" -n openshift-marketplace -ojson 2>/dev/null)
    
    if [ -z "${json_output}" ]; then
        print_error "Failed to get packagemanifest ${NFD_PACKAGE_MANIFEST}" >&2
        exit 1
    fi
    
    starting_csv=$(echo "${json_output}" | jq -r --arg ch "${channel}" '.status.channels[] | select(.name == $ch) | .currentCSV' 2>/dev/null)
    
    if [ -z "${starting_csv}" ] || [ "${starting_csv}" == "null" ]; then
        print_error "Failed to get startingCSV for NFD channel ${channel}" >&2
        print_error "Available channels:" >&2
        echo "${json_output}" | jq -r '.status.channels[].name' 2>/dev/null || true >&2
        exit 1
    fi
    
    print_info "Found NFD startingCSV: ${starting_csv}" >&2
    echo "${starting_csv}"
}

# Function to apply NFD Subscription
apply_nfd_subscription() {
    print_info "Applying NFD Subscription..."
    
    # Get channel and startingCSV dynamically
    local channel
    channel=$(get_nfd_channel)
    
    local starting_csv
    starting_csv=$(get_nfd_starting_csv "${channel}")
    
    # Get script directory to save subscription file
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local subscription_dir="${script_dir}/nfd-operator"
    local subscription_file="${subscription_dir}/subscription.yaml"
    
    # Ensure directory exists
    if [ ! -d "${subscription_dir}" ]; then
        print_error "Directory ${subscription_dir} does not exist!"
        exit 1
    fi
    
    print_info "Creating NFD subscription YAML file: ${subscription_file}"
    
    cat <<EOF > "${subscription_file}"
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${NFD_SUBSCRIPTION_NAME}
  namespace: ${NFD_NAMESPACE}
spec:
  channel: ${channel}
  installPlanApproval: Manual
  name: ${NFD_PACKAGE_MANIFEST}
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: ${starting_csv}
EOF
    
    # Apply the subscription
    oc apply -f "${subscription_file}"
    
    print_info "NFD Subscription applied successfully"
    print_info "Subscription YAML saved to: ${subscription_file}"
}

# Function to wait for NFD operator installation
wait_for_nfd_operator() {
    print_info "Waiting for NFD Operator to be installed..."
    print_info "This may take a few minutes..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if oc get csv -n "${NFD_NAMESPACE}" -o jsonpath='{.items[*].status.phase}' | grep -q "Succeeded"; then
            print_info "NFD Operator installed successfully!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 10
    done
    
    echo ""
    print_warn "NFD Operator installation is taking longer than expected."
    print_info "You can check the status manually with:"
    print_info "  oc get csv -n ${NFD_NAMESPACE}"
    print_info "  oc get pods -n ${NFD_NAMESPACE}"
}

# Function to apply NodeFeatureDiscovery CR
apply_nfd_cr() {
    print_info "Applying NodeFeatureDiscovery CR: ${NFD_CR_NAME}"
    
    # Get script directory to find the NFD YAML file
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local nfd_yaml_file="${script_dir}/nfd-operator/nfd-instance.yaml"
    
    if [ ! -f "${nfd_yaml_file}" ]; then
        print_error "NFD YAML file not found: ${nfd_yaml_file}"
        print_error "Please ensure the nfd-operator/nfd-instance.yaml file exists in the script directory."
        exit 1
    fi
    
    print_info "Applying NFD configuration from: ${nfd_yaml_file}"
    oc apply -f "${nfd_yaml_file}"
    
    if [ $? -eq 0 ]; then
        print_info "NodeFeatureDiscovery CR ${NFD_CR_NAME} applied successfully"
    else
        print_error "Failed to apply NodeFeatureDiscovery CR"
        exit 1
    fi
}

# Function to wait for NFD pods
wait_for_nfd_pods() {
    print_info "Waiting for NFD pods to be ready..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local ready_pods
        ready_pods=$(oc get pods -n "${NFD_NAMESPACE}" -l app=nfd-master --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        
        if [ "${ready_pods}" -gt 0 ]; then
            print_info "NFD pods are running!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 10
    done
    
    echo ""
    print_warn "NFD pods are taking longer than expected to start."
    print_info "You can check the status manually with:"
    print_info "  oc get pods -n ${NFD_NAMESPACE}"
}

# Function to apply ClusterPolicy
apply_cluster_policy() {
    print_info "Applying ClusterPolicy for NVIDIA GPU Operator..."
    
    # Get script directory to find the ClusterPolicy YAML file
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local cluster_policy_file="${script_dir}/nvidia-operator/cluster-policy.yaml"
    
    if [ ! -f "${cluster_policy_file}" ]; then
        print_error "ClusterPolicy YAML file not found: ${cluster_policy_file}"
        print_error "Please ensure the nvidia-operator/cluster-policy.yaml file exists."
        exit 1
    fi
    
    print_info "Applying ClusterPolicy from: ${cluster_policy_file}"
    oc apply -f "${cluster_policy_file}"
    
    if [ $? -eq 0 ]; then
        print_info "ClusterPolicy applied successfully"
    else
        print_error "Failed to apply ClusterPolicy"
        exit 1
    fi
}

# Function to create cert-manager namespace
create_certmanager_namespace() {
    print_info "Creating cert-manager namespace: ${CERTMANAGER_NAMESPACE}"
    
    if oc get namespace "${CERTMANAGER_NAMESPACE}" &> /dev/null; then
        print_warn "Namespace ${CERTMANAGER_NAMESPACE} already exists. Skipping creation."
        return
    fi
    
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local namespace_file="${script_dir}/cert-manager/namespace.yaml"
    
    if [ ! -f "${namespace_file}" ]; then
        print_error "cert-manager namespace YAML file not found: ${namespace_file}"
        exit 1
    fi
    
    oc apply -f "${namespace_file}"
    print_info "Namespace ${CERTMANAGER_NAMESPACE} created successfully"
}

# Function to apply cert-manager OperatorGroup
apply_certmanager_operator_group() {
    print_info "Applying cert-manager OperatorGroup..."
    
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local og_file="${script_dir}/cert-manager/operatorgroup.yaml"
    
    if [ ! -f "${og_file}" ]; then
        print_error "cert-manager OperatorGroup YAML file not found: ${og_file}"
        exit 1
    fi
    
    oc apply -f "${og_file}"
    print_info "cert-manager OperatorGroup applied successfully"
}

# Function to get cert-manager channel from packagemanifest
get_certmanager_channel() {
    print_info "Getting default channel from cert-manager packagemanifest..." >&2
    
    local channel
    channel=$(oc get packagemanifest "${CERTMANAGER_PACKAGE_MANIFEST}" -n openshift-marketplace -o jsonpath='{.status.defaultChannel}' 2>/dev/null)
    
    if [ -z "${channel}" ]; then
        print_error "Failed to get channel from packagemanifest ${CERTMANAGER_PACKAGE_MANIFEST}" >&2
        exit 1
    fi
    
    print_info "Found cert-manager channel: ${channel}" >&2
    echo "${channel}"
}

# Function to get cert-manager startingCSV from packagemanifest
get_certmanager_starting_csv() {
    local channel=$1
    print_info "Getting startingCSV for cert-manager channel: ${channel}" >&2
    
    local starting_csv
    local json_output
    json_output=$(oc get packagemanifests/"${CERTMANAGER_PACKAGE_MANIFEST}" -n openshift-marketplace -ojson 2>/dev/null)
    
    if [ -z "${json_output}" ]; then
        print_error "Failed to get packagemanifest ${CERTMANAGER_PACKAGE_MANIFEST}" >&2
        exit 1
    fi
    
    starting_csv=$(echo "${json_output}" | jq -r --arg ch "${channel}" '.status.channels[] | select(.name == $ch) | .currentCSV' 2>/dev/null)
    
    if [ -z "${starting_csv}" ] || [ "${starting_csv}" == "null" ]; then
        print_error "Failed to get startingCSV for cert-manager channel ${channel}" >&2
        exit 1
    fi
    
    print_info "Found cert-manager startingCSV: ${starting_csv}" >&2
    echo "${starting_csv}"
}

# Function to apply cert-manager Subscription
apply_certmanager_subscription() {
    print_info "Applying cert-manager Subscription..."
    
    local channel
    channel=$(get_certmanager_channel)
    
    local starting_csv
    starting_csv=$(get_certmanager_starting_csv "${channel}")
    
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local subscription_dir="${script_dir}/cert-manager"
    local subscription_file="${subscription_dir}/subscription.yaml"
    
    if [ ! -d "${subscription_dir}" ]; then
        print_error "Directory ${subscription_dir} does not exist!"
        exit 1
    fi
    
    print_info "Creating cert-manager subscription YAML file: ${subscription_file}"
    
    cat <<EOF > "${subscription_file}"
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${CERTMANAGER_SUBSCRIPTION_NAME}
  namespace: ${CERTMANAGER_NAMESPACE}
spec:
  channel: ${channel}
  installPlanApproval: Manual
  name: ${CERTMANAGER_PACKAGE_MANIFEST}
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: ${starting_csv}
EOF
    
    oc apply -f "${subscription_file}"
    
    print_info "cert-manager Subscription applied successfully"
    print_info "Subscription YAML saved to: ${subscription_file}"
}

# Function to wait for cert-manager operator installation
wait_for_certmanager_operator() {
    print_info "Waiting for cert-manager Operator to be installed..."
    print_info "This may take a few minutes..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if oc get csv -n "${CERTMANAGER_NAMESPACE}" -o jsonpath='{.items[*].status.phase}' | grep -q "Succeeded"; then
            print_info "cert-manager Operator installed successfully!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 10
    done
    
    echo ""
    print_warn "cert-manager Operator installation is taking longer than expected."
    print_info "You can check the status manually with:"
    print_info "  oc get csv -n ${CERTMANAGER_NAMESPACE}"
    print_info "  oc get pods -n ${CERTMANAGER_NAMESPACE}"
}

# Function to deploy MinIO
deploy_minio() {
    print_info "Deploying MinIO object storage..."
    
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local minio_dir="${script_dir}/minio"
    
    if [ ! -d "${minio_dir}" ]; then
        print_error "MinIO manifests directory not found: ${minio_dir}"
        exit 1
    fi
    
    local files=("namespace.yaml" "secret.yaml" "pvc.yaml" "deployment.yaml" "service.yaml" "route.yaml")
    
    for file in "${files[@]}"; do
        local filepath="${minio_dir}/${file}"
        if [ ! -f "${filepath}" ]; then
            print_error "MinIO manifest not found: ${filepath}"
            exit 1
        fi
        print_info "Applying ${file}..."
        oc apply -f "${filepath}"
    done
    
    print_info "MinIO manifests applied successfully"
}

# Function to wait for MinIO deployment to be ready
wait_for_minio() {
    print_info "Waiting for MinIO deployment to be ready..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local ready
        ready=$(oc get deployment minio -n "${MINIO_NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        
        if [ "${ready}" -ge 1 ] 2>/dev/null; then
            print_info "MinIO is ready!"
            local api_route
            api_route=$(oc get route minio-api -n "${MINIO_NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
            local console_route
            console_route=$(oc get route minio-console -n "${MINIO_NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
            if [ -n "${api_route}" ]; then
                print_info "MinIO API endpoint: https://${api_route}"
            fi
            if [ -n "${console_route}" ]; then
                print_info "MinIO Console: https://${console_route}"
            fi
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 10
    done
    
    echo ""
    print_warn "MinIO deployment is taking longer than expected."
    print_info "You can check the status manually with:"
    print_info "  oc get pods -n ${MINIO_NAMESPACE}"
    print_info "  oc get deployment minio -n ${MINIO_NAMESPACE}"
}

 # Function to create OpenShift AI namespaces
create_rhoai_namespaces() {
    print_info "Creating OpenShift AI namespaces..."
    
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Create redhat-ods-operator namespace
    local operator_ns_file="${script_dir}/openshift-ai/namespace-operator.yaml"
    if [ -f "${operator_ns_file}" ]; then
        print_info "Creating namespace: ${RHOAI_OPERATOR_NAMESPACE}"
        oc apply -f "${operator_ns_file}"
    else
        print_error "Namespace file not found: ${operator_ns_file}"
        exit 1
    fi
    
    # Create redhat-ods-applications namespace
    local applications_ns_file="${script_dir}/openshift-ai/namespace-applications.yaml"
    if [ -f "${applications_ns_file}" ]; then
        print_info "Creating namespace: ${RHOAI_APPLICATIONS_NAMESPACE}"
        oc apply -f "${applications_ns_file}"
    else
        print_error "Namespace file not found: ${applications_ns_file}"
        exit 1
    fi
    
    # Create rhods-notebooks namespace
    local notebooks_ns_file="${script_dir}/openshift-ai/namespace-notebooks.yaml"
    if [ -f "${notebooks_ns_file}" ]; then
        print_info "Creating namespace: ${RHOAI_NOTEBOOKS_NAMESPACE}"
        oc apply -f "${notebooks_ns_file}"
    else
        print_error "Namespace file not found: ${notebooks_ns_file}"
        exit 1
    fi
    
    print_info "OpenShift AI namespaces created successfully"
}

# Function to get RHOAI channel from packagemanifest
get_rhoai_channel() {
    print_info "Getting default channel from RHOAI packagemanifest..." >&2
    
    local channel
    channel=$(oc get packagemanifest "${RHOAI_PACKAGE_MANIFEST}" -n openshift-marketplace -o jsonpath='{.status.defaultChannel}' 2>/dev/null)
    
    if [ -z "${channel}" ]; then
        print_error "Failed to get channel from packagemanifest ${RHOAI_PACKAGE_MANIFEST}" >&2
        print_error "Make sure the packagemanifest exists in openshift-marketplace namespace" >&2
        exit 1
    fi
    
    print_info "Found RHOAI channel: ${channel}" >&2
    echo "${channel}"
}

# Function to get RHOAI startingCSV from packagemanifest
get_rhoai_starting_csv() {
    local channel=$1
    print_info "Getting startingCSV for RHOAI channel: ${channel}" >&2
    
    local starting_csv
    local json_output
    json_output=$(oc get packagemanifests/"${RHOAI_PACKAGE_MANIFEST}" -n openshift-marketplace -ojson 2>/dev/null)
    
    if [ -z "${json_output}" ]; then
        print_error "Failed to get packagemanifest ${RHOAI_PACKAGE_MANIFEST}" >&2
        exit 1
    fi
    
    starting_csv=$(echo "${json_output}" | jq -r --arg ch "${channel}" '.status.channels[] | select(.name == $ch) | .currentCSV' 2>/dev/null)
    
    if [ -z "${starting_csv}" ] || [ "${starting_csv}" == "null" ]; then
        print_error "Failed to get startingCSV for RHOAI channel ${channel}" >&2
        print_error "Available channels:" >&2
        echo "${json_output}" | jq -r '.status.channels[].name' 2>/dev/null || true >&2
        exit 1
    fi
    
    print_info "Found RHOAI startingCSV: ${starting_csv}" >&2
    echo "${starting_csv}"
}

# Function to apply RHOAI OperatorGroup
apply_rhoai_operator_group() {
    print_info "Applying OpenShift AI OperatorGroup: ${RHOAI_OPERATOR_GROUP_NAME}"
    
    # Get script directory to find the YAML file
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local og_file="${script_dir}/openshift-ai/operatorgroup.yaml"
    
    if [ ! -f "${og_file}" ]; then
        print_error "OpenShift AI OperatorGroup YAML file not found: ${og_file}"
        exit 1
    fi
    
    oc apply -f "${og_file}"
    print_info "OpenShift AI OperatorGroup applied successfully"
}

# Function to apply RHOAI Subscription
apply_rhoai_subscription() {
    print_info "Applying OpenShift AI Subscription: ${RHOAI_SUBSCRIPTION_NAME}"
    
    # Get channel and startingCSV dynamically
    local channel
    channel=$(get_rhoai_channel)
    
    local starting_csv
    starting_csv=$(get_rhoai_starting_csv "${channel}")
    
    # Get script directory to save subscription file
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local subscription_dir="${script_dir}/openshift-ai"
    local subscription_file="${subscription_dir}/subscription.yaml"
    
    # Ensure directory exists
    if [ ! -d "${subscription_dir}" ]; then
        print_error "Directory ${subscription_dir} does not exist!"
        exit 1
    fi
    
    print_info "Creating OpenShift AI subscription YAML file: ${subscription_file}"
    
    cat <<EOF > "${subscription_file}"
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${RHOAI_SUBSCRIPTION_NAME}
  namespace: ${RHOAI_OPERATOR_NAMESPACE}
spec:
  channel: ${channel}
  installPlanApproval: Manual
  name: ${RHOAI_PACKAGE_MANIFEST}
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: ${starting_csv}
EOF
    
    # Apply the subscription
    oc apply -f "${subscription_file}"
    
    print_info "OpenShift AI Subscription applied successfully"
    print_info "Subscription YAML saved to: ${subscription_file}"
}

# Function to wait for RHOAI operator installation
wait_for_rhoai_operator() {
    print_info "Waiting for OpenShift AI Operator to be installed..."
    print_info "This may take a few minutes..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if oc get csv -n "${RHOAI_OPERATOR_NAMESPACE}" -o jsonpath='{.items[*].status.phase}' | grep -q "Succeeded"; then
            print_info "OpenShift AI Operator installed successfully!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 10
    done
    
    echo ""
    print_warn "OpenShift AI Operator installation is taking longer than expected."
    print_info "You can check the status manually with:"
    print_info "  oc get csv -n ${RHOAI_OPERATOR_NAMESPACE}"
    print_info "  oc get pods -n ${RHOAI_OPERATOR_NAMESPACE}"
}

# Function to apply DataScienceCluster CR
apply_datasciencecluster() {
    print_info "Applying DataScienceCluster CR: default-dsc"
    
    # Get script directory to find the DataScienceCluster YAML file
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local dsc_file="${script_dir}/openshift-ai/datasciencecluster.yaml"
    
    if [ ! -f "${dsc_file}" ]; then
        print_error "DataScienceCluster YAML file not found: ${dsc_file}"
        print_error "Please ensure the openshift-ai/datasciencecluster.yaml file exists."
        exit 1
    fi
    
    print_info "Applying DataScienceCluster from: ${dsc_file}"
    oc apply -f "${dsc_file}"
    
    if [ $? -eq 0 ]; then
        print_info "DataScienceCluster CR applied successfully"
        print_info "Note: All components are set to 'Removed' state. Enable them as needed by changing managementState to 'Managed'."
    else
        print_error "Failed to apply DataScienceCluster CR"
        exit 1
    fi
}

# Function to display installation status
show_status() {
    print_info "Installation Status:"
    echo ""
    
    echo "=== NVIDIA GPU Operator ==="
    echo "Namespace:"
    oc get namespace "${NAMESPACE}" 2>/dev/null || print_error "Namespace not found"
    echo ""
    
    echo "OperatorGroup:"
    oc get operatorgroup -n "${NAMESPACE}" 2>/dev/null || print_error "OperatorGroup not found"
    echo ""
    
    echo "Subscription:"
    oc get subscription -n "${NAMESPACE}" 2>/dev/null || print_error "Subscription not found"
    echo ""
    
    echo "ClusterServiceVersion (CSV):"
    oc get csv -n "${NAMESPACE}" 2>/dev/null || print_warn "CSV not yet created"
    echo ""
    
    echo "Operator Pods:"
    oc get pods -n "${NAMESPACE}" 2>/dev/null || print_warn "No pods found yet"
    echo ""
    
    echo "=== Node Feature Discovery Operator ==="
    echo "Namespace:"
    oc get namespace "${NFD_NAMESPACE}" 2>/dev/null || print_error "NFD Namespace not found"
    echo ""
    
    echo "OperatorGroup:"
    oc get operatorgroup -n "${NFD_NAMESPACE}" 2>/dev/null || print_error "NFD OperatorGroup not found"
    echo ""
    
    echo "Subscription:"
    oc get subscription -n "${NFD_NAMESPACE}" 2>/dev/null || print_error "NFD Subscription not found"
    echo ""
    
    echo "ClusterServiceVersion (CSV):"
    oc get csv -n "${NFD_NAMESPACE}" 2>/dev/null || print_warn "NFD CSV not yet created"
    echo ""
    
    echo "NodeFeatureDiscovery CR:"
    oc get nodefeaturediscovery -n "${NFD_NAMESPACE}" 2>/dev/null || print_warn "NFD CR not yet created"
    echo ""
    
    echo "NFD Pods:"
    oc get pods -n "${NFD_NAMESPACE}" 2>/dev/null || print_warn "No NFD pods found yet"
    echo ""
    
    echo "=== cert-manager Operator ==="
    echo "Namespace:"
    oc get namespace "${CERTMANAGER_NAMESPACE}" 2>/dev/null || print_error "cert-manager Namespace not found"
    echo ""
    
    echo "Subscription:"
    oc get subscription -n "${CERTMANAGER_NAMESPACE}" 2>/dev/null || print_error "cert-manager Subscription not found"
    echo ""
    
    echo "ClusterServiceVersion (CSV):"
    oc get csv -n "${CERTMANAGER_NAMESPACE}" 2>/dev/null || print_warn "cert-manager CSV not yet created"
    echo ""
    
    echo "cert-manager Pods:"
    oc get pods -n cert-manager 2>/dev/null || print_warn "No cert-manager pods found yet"
    echo ""
    
    echo "=== MinIO Object Storage ==="
    echo "Namespace:"
    oc get namespace "${MINIO_NAMESPACE}" 2>/dev/null || print_error "MinIO Namespace not found"
    echo ""
    
    echo "Deployment:"
    oc get deployment -n "${MINIO_NAMESPACE}" 2>/dev/null || print_warn "No MinIO deployment found"
    echo ""
    
    echo "Pods:"
    oc get pods -n "${MINIO_NAMESPACE}" 2>/dev/null || print_warn "No MinIO pods found"
    echo ""
    
    echo "Routes:"
    oc get routes -n "${MINIO_NAMESPACE}" 2>/dev/null || print_warn "No MinIO routes found"
    echo ""
    
    echo "=== Red Hat OpenShift AI Operator ==="
    echo "Operator Namespace:"
    oc get namespace "${RHOAI_OPERATOR_NAMESPACE}" 2>/dev/null || print_error "RHOAI Operator Namespace not found"
    echo ""
    
    echo "Applications Namespace:"
    oc get namespace "${RHOAI_APPLICATIONS_NAMESPACE}" 2>/dev/null || print_error "RHOAI Applications Namespace not found"
    echo ""
    
    echo "Notebooks Namespace:"
    oc get namespace "${RHOAI_NOTEBOOKS_NAMESPACE}" 2>/dev/null || print_error "RHOAI Notebooks Namespace not found"
    echo ""
    
    echo "OperatorGroup:"
    oc get operatorgroup -n "${RHOAI_OPERATOR_NAMESPACE}" 2>/dev/null || print_error "RHOAI OperatorGroup not found"
    echo ""
    
    echo "Subscription:"
    oc get subscription -n "${RHOAI_OPERATOR_NAMESPACE}" 2>/dev/null || print_error "RHOAI Subscription not found"
    echo ""
    
    echo "ClusterServiceVersion (CSV):"
    oc get csv -n "${RHOAI_OPERATOR_NAMESPACE}" 2>/dev/null || print_warn "RHOAI CSV not yet created"
    echo ""
    
    echo "RHOAI Operator Pods:"
    oc get pods -n "${RHOAI_OPERATOR_NAMESPACE}" 2>/dev/null || print_warn "No RHOAI operator pods found yet"
    echo ""
    
    echo "DataScienceCluster:"
    oc get datasciencecluster -A 2>/dev/null || print_warn "DataScienceCluster not yet created"
    echo ""
}

# Main execution
main() {
    print_info "Starting NVIDIA GPU Operator and NFD Operator installation..."
    echo ""
    print_info "IMPORTANT: NFD Operator must be installed and operational BEFORE NVIDIA GPU Operator!"
    echo ""
    
    check_prerequisites
    echo ""
    
    # ====================================================================
    # STEP 1: Install NFD Operator FIRST (REQUIRED PREREQUISITE)
    # ====================================================================
    # The NVIDIA GPU Operator depends on Node Feature Discovery (NFD)
    # to detect and label GPU-enabled nodes. NFD MUST be fully installed
    # and operational before proceeding with GPU Operator installation.
    # ====================================================================
    print_info "=== STEP 1: Installing Node Feature Discovery (NFD) Operator ==="
    echo ""
    
    create_nfd_namespace
    echo ""
    
    apply_nfd_operator_group
    echo ""
    
    apply_nfd_subscription
    echo ""
    
    approve_installplan "${NFD_NAMESPACE}" "NFD Operator"
    echo ""
    
    wait_for_nfd_operator
    echo ""
    
    apply_nfd_cr
    echo ""
    
    wait_for_nfd_pods
    echo ""
    
    # Verify NFD is fully operational before proceeding
    print_info "Verifying NFD Operator is fully operational..."
    local nfd_ready=false
    local max_checks=12
    local check_count=0
    
    while [ $check_count -lt $max_checks ]; do
        if oc get nodefeaturediscovery "${NFD_CR_NAME}" -n "${NFD_NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null | grep -q "True"; then
            nfd_ready=true
            break
        fi
        check_count=$((check_count + 1))
        echo -n "."
        sleep 10
    done
    
    echo ""
    if [ "${nfd_ready}" = true ]; then
        print_info "NFD Operator is ready! Proceeding with NVIDIA GPU Operator installation..."
    else
        print_warn "NFD Operator may not be fully ready, but proceeding with GPU Operator installation..."
        print_warn "You may need to verify NFD status manually: oc get nodefeaturediscovery -n ${NFD_NAMESPACE}"
    fi
    echo ""
    
    # ====================================================================
    # STEP 2: Install NVIDIA GPU Operator (AFTER NFD is ready)
    # ====================================================================
    # Only proceed with GPU Operator installation after NFD is confirmed
    # to be operational. This ensures proper node feature detection.
    # ====================================================================
    print_info "=== STEP 2: Installing NVIDIA GPU Operator (NFD prerequisite satisfied) ==="
    echo ""
    
    create_namespace
    enable_namespace_monitoring
    echo ""
    
    create_operator_group
    echo ""
    
    create_subscription
    echo ""
    
    approve_installplan "${NAMESPACE}" "NVIDIA GPU Operator"
    echo ""
    
    wait_for_operator
    echo ""
    
    apply_cluster_policy
    echo ""
    
    # ====================================================================
    # STEP 3: Install cert-manager Operator
    # ====================================================================
    print_info "=== STEP 3: Installing cert-manager Operator ==="
    echo ""
    
    create_certmanager_namespace
    echo ""
    
    apply_certmanager_operator_group
    echo ""
    
    apply_certmanager_subscription
    echo ""
    
    approve_installplan "${CERTMANAGER_NAMESPACE}" "cert-manager Operator"
    echo ""
    
    wait_for_certmanager_operator
    echo ""
    
    # ====================================================================
    # STEP 4: Deploy MinIO (pre-requisite for OpenShift AI)
    # ====================================================================
    print_info "=== STEP 4: Deploying MinIO Object Storage ==="
    echo ""
    
    deploy_minio
    echo ""
    
    wait_for_minio
    echo ""
    
    # ====================================================================
    # STEP 5: Install OpenShift AI (after all prerequisites are ready)
    # ====================================================================
    print_info "=== STEP 5: Installing Red Hat OpenShift AI ==="
    echo ""
    
    create_rhoai_namespaces
    echo ""
    
    apply_rhoai_operator_group
    echo ""
    
    apply_rhoai_subscription
    echo ""
    
    approve_installplan "${RHOAI_OPERATOR_NAMESPACE}" "OpenShift AI Operator"
    echo ""
    
    wait_for_rhoai_operator
    echo ""
    
    apply_datasciencecluster
    echo ""
    
    show_status
    
    print_info "Installation process completed!"
    print_info "Next steps:"
    print_info "  1. Label your GPU nodes: oc label node <node-name> nvidia.com/gpu.present=true"
    print_info "  2. Verify GPU nodes: oc get nodes -l nvidia.com/gpu.present=true"
    print_info "  3. Verify ClusterPolicy: oc get clusterpolicy gpu-cluster-policy"
    print_info "  4. Verify NFD is working: oc get nodefeaturediscovery -n ${NFD_NAMESPACE}"
    print_info "  5. Install OpenShift AI components via DataScienceCluster CR"
    print_info "  6. Access OpenShift AI dashboard after components are installed"
}

# Run main function
main
