default readme for example

## 1. EFS Setup for Shared Model Storage

### Create EFS Filesystem
```bash
# Create EFS filesystem
aws efs create-file-system \
    --creation-token neuron-models-$(date +%s) \
    --performance-mode generalPurpose \
    --throughput-mode provisioned \
    --provisioned-throughput-in-mibps 1000 \
    --tags Key=Name,Value=neuron-disaggregated-efs

# Get the filesystem ID
EFS_ID=$(aws efs describe-file-systems \
    --query 'FileSystems[?Tags[?Key==`Name`&&Value==`neuron-disaggregated-efs`]].FileSystemId' \
    --output text)

# Create mount targets in each subnet
for subnet in subnet-xxx subnet-yyy subnet-zzz; do
    aws efs create-mount-target \
        --file-system-id $EFS_ID \
        --subnet-id $subnet \
        --security-groups sg-your-efs-security-group
done
```


### EFS CSI Driver Installation
```bash
# Install EFS CSI Driver
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.7"

# Create StorageClass
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: ${EFS_ID}
  directoryPerms: "0755"
EOF
```