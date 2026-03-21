# OpenShift AI Full Stack Deployment

Automated deployment of the complete GPU + AI stack on Red Hat OpenShift, including all operator prerequisites and supporting infrastructure.

## Prerequisites

- Access to an OpenShift cluster with **cluster administrator** privileges
- OpenShift CLI (`oc`) installed and authenticated (`oc login`)
- Python 3 with `pip`
- Cluster nodes with NVIDIA GPUs (for GPU workloads)

## Components

The deployment installs the following components in order:

| Step | Component                        | Purpose                                                     |
| ---- | -------------------------------- | ----------------------------------------------------------- |
| 1    | **Node Feature Discovery (NFD)** | Detects hardware features on nodes (GPU labels)             |
| 2    | **NVIDIA GPU Operator**          | Manages GPU drivers, device plugin, DCGM, toolkit           |
| 3    | **cert-manager Operator**        | TLS certificate management (required by Kueue)              |
| 4    | **Kueue Operator**               | Job queueing with Ray/PyTorch/batch integrations            |
| 5    | **MinIO**                        | S3-compatible object storage for pipelines and models       |
| 6    | **Red Hat OpenShift AI**         | AI/ML platform (dashboard, workbenches, pipelines, serving) |

### DataScienceCluster Components

The following OpenShift AI components are enabled (`Managed`) in the DSC:

| Component           | Status  | Notes                                                    |
| ------------------- | ------- | -------------------------------------------------------- |
| Dashboard           | Managed | Web UI for AI/ML workflows                               |
| Workbenches         | Managed | Jupyter notebooks in `rhods-notebooks`                   |
| Model Registry      | Managed | Model versioning in `rhoai-model-registries`             |
| AI Pipelines        | Managed | Kubeflow Pipelines 2.0 with Argo controllers             |
| KServe              | Managed | Single-model serving (requires ServiceMesh + Serverless) |
| Ray                 | Managed | Distributed computing (uses standalone Kueue)            |
| Kueue (embedded)    | Removed | Deprecated; replaced by standalone Kueue Operator        |
| Training Operator   | Removed |                                                          |
| Feast Operator      | Removed |                                                          |
| TrustyAI            | Removed |                                                          |
| LlamaStack Operator | Removed |                                                          |

> **Note:** KServe requires **Red Hat OpenShift Service Mesh** and **Red Hat OpenShift Serverless** operators, which are not yet included in this automation. Either add them manually or set `kserve.managementState: Removed` if not needed.

## Project Structure

```
ocp-ai/
├── ansible/                             # Ansible automation (recommended)
│   ├── playbook.yaml                    # Main playbook
│   ├── requirements.yaml                # Ansible collection dependencies
│   ├── group_vars/
│   │   └── all.yaml                     # Variables for all roles
│   └── roles/
│       ├── prerequisites/tasks/main.yaml
│       ├── nfd_operator/tasks/main.yaml
│       ├── nvidia_gpu_operator/tasks/main.yaml
│       ├── cert_manager/tasks/main.yaml
│       ├── kueue_operator/tasks/main.yaml
│       ├── minio/tasks/main.yaml
│       └── openshift_ai/tasks/main.yaml
│
├── nfd-operator/                        # NFD manifests
│   ├── namespace.yaml
│   ├── operatorgroup.yaml
│   ├── subscription.yaml.template
│   └── nfd-instance.yaml
│
├── nvidia-operator/                     # NVIDIA GPU Operator manifests
│   ├── namespace.yaml
│   ├── operatorgroup.yaml
│   ├── subscription.yaml.template
│   └── cluster-policy.yaml
│
├── cert-manager/                        # cert-manager Operator manifests
│   ├── namespace.yaml
│   └── operatorgroup.yaml
│
├── kueue-operator/                      # Kueue Operator manifests
│   ├── namespace.yaml
│   ├── operatorgroup.yaml
│   ├── subscription.yaml.template
│   ├── kueue-instance.yaml              # Kueue CR with framework integrations
│   └── kueue-system.yaml               # KueueViz project + RBAC
│
├── minio/                               # MinIO object storage manifests
│   ├── namespace.yaml
│   ├── secret.yaml
│   ├── pvc.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── route.yaml
│
├── openshift-ai/                        # OpenShift AI manifests
│   ├── namespace-operator.yaml
│   ├── namespace-applications.yaml
│   ├── namespace-notebooks.yaml
│   ├── operatorgroup.yaml
│   ├── subscription.yaml.template
│   ├── datasciencecluster.yaml
│   └── secrets/
│       └── minio-s3-connection.yaml     # MinIO S3 connection for data science projects
│
├── install-nvidia-gpu-operator.sh       # Legacy shell script
└── README.md
```

## Installation with Ansible

### 1. Install dependencies

```bash
pip install ansible kubernetes openshift
ansible-galaxy collection install -r ansible/requirements.yaml
```

### 2. Log in to your OpenShift cluster

```bash
oc login --server=https://api.your-cluster.example.com:6443 -u kubeadmin
```

### 3. Run the playbook

```bash
ansible-playbook ansible/playbook.yaml
```

### Run specific steps with tags

Each role has a tag for selective execution:

```bash
# Install only MinIO
ansible-playbook ansible/playbook.yaml --tags minio

# Install cert-manager and Kueue together
ansible-playbook ansible/playbook.yaml --tags cert-manager,kueue

# Install everything except GPU operators
ansible-playbook ansible/playbook.yaml --skip-tags nfd,nvidia

# Run only OpenShift AI
ansible-playbook ansible/playbook.yaml --tags rhoai
```

Available tags: `prerequisites`, `nfd`, `nvidia`, `cert-manager`, `kueue`, `minio`, `rhoai`, `operators`, `storage`

### Dry run and debugging

```bash
# Preview changes without applying
ansible-playbook ansible/playbook.yaml --check

# Verbose output
ansible-playbook ansible/playbook.yaml -v

# List all tasks
ansible-playbook ansible/playbook.yaml --list-tasks
```

## Configuration

All variables are defined in `ansible/group_vars/all.yaml`:

| Variable                   | Default                    | Description                         |
| -------------------------- | -------------------------- | ----------------------------------- |
| `nfd_namespace`            | `openshift-nfd`            | NFD operator namespace              |
| `nvidia_namespace`         | `nvidia-gpu-operator`      | NVIDIA operator namespace           |
| `certmanager_namespace`    | `cert-manager-operator`    | cert-manager namespace              |
| `kueue_namespace`          | `openshift-kueue-operator` | Kueue operator namespace            |
| `minio_namespace`          | `minio`                    | MinIO namespace                     |
| `rhoai_operator_namespace` | `redhat-ods-operator`      | OpenShift AI operator namespace     |
| `operator_install_timeout` | `600`                      | Seconds to wait for operator CSV    |
| `minio_ready_timeout`      | `300`                      | Seconds to wait for MinIO readiness |

## Verification

After installation, verify the stack:

```bash
# NFD
oc get nodefeaturediscovery -n openshift-nfd
oc get pods -n openshift-nfd

# NVIDIA GPU Operator
oc get clusterpolicy gpu-cluster-policy
oc get pods -n nvidia-gpu-operator

# cert-manager
oc get csv -n cert-manager-operator
oc get pods -n cert-manager

# Kueue
oc get kueue cluster -n openshift-kueue-operator
oc get pods -n openshift-kueue-operator
oc get pods -n kueue-system

# MinIO
oc get deployment minio -n minio
oc get routes -n minio

# OpenShift AI
oc get datasciencecluster default-dsc
oc get pods -n redhat-ods-operator
oc get pods -n redhat-ods-applications
```

## Post-Installation

1. **Label GPU nodes** (if not auto-detected):

   ```bash
   oc label node <node-name> nvidia.com/gpu.present=true
   ```

2. **Taint GPU nodes** (recommended for Kueue scheduling):

   ```bash
   oc adm taint nodes <gpu-node> nvidia.com/gpu=Exists:NoSchedule
   ```

3. **Access MinIO Console** -- get the route URL:

   ```bash
   oc get route minio-console -n minio -o jsonpath='{.spec.host}'
   ```

   Login with `admin` / `123456`.

4. **Access OpenShift AI Dashboard**:

   ```bash
   oc get route -n redhat-ods-applications -l app=rhods-dashboard
   ```

5. **Update the MinIO S3 connection secret** in `openshift-ai/secrets/minio-s3-connection.yaml` with your actual credentials before using pipelines.

## Troubleshooting

### Multiple OperatorGroups in namespace

```
csv created in namespace with multiple operatorgroups, can't pick one automatically
```

List and remove the extra OperatorGroup:

```bash
oc get operatorgroup -n <namespace>
oc delete operatorgroup <extra-name> -n <namespace>
```

### OwnNamespace InstallModeType not supported

The OpenShift AI Operator requires AllNamespaces mode. Its OperatorGroup uses `spec: {}` (no `targetNamespaces`).

### Operator CSV stuck in Pending

Check if the InstallPlan needs approval:

```bash
oc get installplan -n <namespace>
oc patch installplan <name> -n <namespace> --type merge -p '{"spec":{"approved":true}}'
```

The Ansible playbook approves InstallPlans automatically.

## Additional Resources

- [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)
- [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [Red Hat build of Kueue Documentation](https://docs.redhat.com/en/documentation/red_hat_build_of_kueue/1.0)
- [Node Feature Discovery Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/specialized_hardware_and_driver_enablement/node-feature-discovery-operator)
- [OpenShift cert-manager Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift)
