CLUSTER_NAME="skills-eks-cluster"
CLUSTER_OIDC=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -c 9-100)
ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)

cat <<\EOF> aws-efs-csi-driver-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/OIDC"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "OIDC:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF

sed -i "s|ACCOUNT_ID|$ACCOUNT|g" aws-efs-csi-driver-trust-policy.json
sed -i "s|OIDC|$CLUSTER_OIDC|g" aws-efs-csi-driver-trust-policy.json

aws iam create-role --role-name AmazonEKS_EFS_CSI_DriverRole --assume-role-policy-document file:///home/ec2-user/aws-efs-csi-driver-trust-policy.json

aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy --role-name AmazonEKS_EFS_CSI_DriverRole

export AWS_REGION=ap-northeast-2

eksctl create addon --name aws-efs-csi-driver --cluster $CLUSTER_NAME --service-account-role-arn arn:aws:iam::$ACCOUNT:role/AmazonEKS_EFS_CSI_DriverRole --force

eksctl delete addon --name aws-efs-csi-driver --cluster $CLUSTER_NAME

aws efs create-file-system \
    --performance-mode generalPurpose \
    --throughput-mode bursting \
    --encrypted \
    --tags Key=Name,Value=skills-efs

BASTION_SG_ID=$(aws ec2 describe-instances --filter Name=tag:Name,Values=skills-bastion --query "Reservations[].Instances[].SecurityGroups[].GroupId" --output text)
EKS_NODE_GROUP_SG_ID=$(aws ec2 describe-instances --filter Name=tag:Name,Values=skills-app-node --query "Reservations[1].Instances[].SecurityGroups[].GroupId" --output text)

aws ec2 authorize-security-group-ingress --group-id $BASTION_SG_ID --protocol tcp --port 2049 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-egress --group-id $BASTION_SG_ID --protocol tcp --port 2049 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-ingress --group-id $EKS_NODE_GROUP_SG_ID --protocol tcp --port 2049 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-egress --group-id $EKS_NODE_GROUP_SG_ID --protocol tcp --port 2049 --cidr 0.0.0.0/0 > /dev/null

EFS_ID=$(aws efs describe-file-systems --query "FileSystems[].FileSystemId" --output text)
sed -i "s|EFS_ID|$EFS_ID|g" statefulset-efs.yaml

# 서브넷 ID 확인
SUBNET_IDS=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.subnetIds" --output text)

# EFS 마운트 타겟 생성 (각 서브넷에 대해)
for SUBNET_ID in $SUBNET_IDS; do
    aws efs create-mount-target \
        --file-system-id $EFS_ID \
        --subnet-id $SUBNET_ID \
        --security-groups $EKS_NODE_GROUP_SG_ID
done

# 마운트 타겟 상태 확인
aws efs describe-mount-targets --file-system-id $EFS_ID

kubectl apply -f statefulset-efs.yaml