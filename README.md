# OpenShift AI Full Stack Deployment

Automated deployment of a complete GPU + AI stack on Red Hat OpenShift. This repository installs the prerequisites, infrastructure, and OpenShift AI components required for GPU-enabled model training and inference.

## What is included

The main Ansible playbook in `ansible/playbook.yaml` deploys:

- Node Feature Discovery (NFD)
- NVIDIA GPU Operator
- cert-manager Operator
- Kueue Operator
- MinIO object storage
- Red Hat OpenShift AI (DataScienceCluster)

The repository also includes manifest templates and role definitions so you can install the full stack or just the components you need.

## Prerequisites

- OpenShift cluster access with **cluster-admin** privileges
- `oc` CLI installed and authenticated
- Python 3 and `pip`
- NVIDIA GPU nodes for GPU workloads and OpenShift AI GPU training

## Quick start

```bash
cd /home/tavelino/ocp-ai
pip install ansible kubernetes openshift
ansible-galaxy collection install -r ansible/requirements.yaml
oc login --server=https://api.your-cluster.example.com:6443 -u kubeadmin
ansible-playbook ansible/playbook.yaml
```

## Deploy only MinIO

If you want to install only MinIO, run:

```bash
cd /home/tavelino/ocp-ai
ansible-playbook ansible/playbook.yaml --tags minio
```

## Selective deployment by tag

Use tags to install or skip specific roles:

```bash
ansible-playbook ansible/playbook.yaml --tags minio
ansible-playbook ansible/playbook.yaml --tags cert-manager,kueue
ansible-playbook ansible/playbook.yaml --skip-tags nfd,nvidia
ansible-playbook ansible/playbook.yaml --tags rhoai
```

Supported tags:
`prerequisites`, `nfd`, `nvidia`, `cert-manager`, `kueue`, `minio`, `rhoai`, `operators`, `storage`

## Project structure

```
ocp-ai/
├── ansible/                             # Ansible automation
│   ├── playbook.yaml                    # Main playbook
│   ├── requirements.yaml                # Ansible collections
│   ├── group_vars/                      # Deployment variables
│   │   └── all.yaml
│   └── roles/                           # Role definitions
├── cert-manager/                        # cert-manager manifests
├── kueue-operator/                      # Kueue manifests
├── minio/                               # MinIO manifests
├── nfd-operator/                        # NFD manifests
├── nvidia-operator/                     # NVIDIA GPU Operator manifests
├── openshift-ai/                        # OpenShift AI manifests and secrets
├── serverless-operator/                 # Serverless manifests
├── servicemesh-operator/                # Service Mesh manifests
└── README.md
```

## Configuration

Review `ansible/group_vars/all.yaml` to customize deployment variables.

Key variables include:

| Variable                   | Default                    | Purpose                                 |
|----------------------------|----------------------------|-----------------------------------------|
| `nfd_namespace`            | `openshift-nfd`            | NFD operator namespace                  |
| `nvidia_namespace`         | `nvidia-gpu-operator`      | NVIDIA operator namespace               |
| `certmanager_namespace`    | `cert-manager-operator`    | cert-manager namespace                  |
| `kueue_namespace`          | `openshift-kueue-operator` | Kueue operator namespace                |
| `minio_namespace`          | `minio`                    | MinIO namespace                         |
| `rhoai_operator_namespace` | `redhat-ods-operator`      | OpenShift AI operator namespace         |
| `operator_install_timeout` | `600`                      | CSV install timeout (seconds)           |
| `minio_ready_timeout`      | `300`                      | MinIO readiness timeout (seconds)       |

## Verify deployment

```bash
oc get pods -n openshift-nfd
oc get clusterpolicy gpu-cluster-policy
oc get pods -n nvidia-gpu-operator
oc get csv -n cert-manager-operator
oc get pods -n cert-manager
oc get pods -n openshift-kueue-operator
oc get pods -n kueue-system
oc get deployment minio -n minio
oc get routes -n minio
oc get datasciencecluster default-dsc
oc get pods -n redhat-ods-operator
oc get pods -n redhat-ods-applications
```

## Post-installation steps

Label GPU-capable nodes:

```bash
oc label node <node-name> nvidia.com/gpu.present=true
```

Find the MinIO console route:

```bash
oc get route minio-console -n minio -o jsonpath='{.spec.host}'
```

Check and configure the OpenShift AI MinIO connection secret in:

- `openshift-ai/secrets/minio-s3-connection.yaml`

## Troubleshooting

### InstallPlan pending

```bash
oc get installplan -n <namespace>
oc patch installplan <name> -n <namespace> --type merge -p '{"spec":{"approved":true}}'
```

### Duplicate OperatorGroup

If you see an error about multiple OperatorGroups:

```bash
oc get operatorgroup -n <namespace>
oc delete operatorgroup <extra-name> -n <namespace>
```

## Resources

- [Red Hat OpenShift AI Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/)
- [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [Red Hat build of Kueue Documentation](https://docs.redhat.com/en/documentation/red_hat_build_of_kueue/1.0)
- [OpenShift NFD Operator Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/specialized_hardware_and_driver_enablement/node-feature-discovery-operator)
- [OpenShift cert-manager Operator Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift)
