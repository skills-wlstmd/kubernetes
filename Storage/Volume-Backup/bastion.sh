export EKS_CLUSTER_NAME=skills-eks-cluster
export EKS_NODE_GROUP_NAME=skills-app-nodegroup
export AWS_REGION=ap-northeast-2

aws ec2 create-volume --size 10 --volume-type gp3 --availability-zone ap-northeast-2a --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=wsi-ebs}]'

cat << EOF > ebs_policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSnapshot",
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots"
            ],
            "Resource": "*"
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name EBSforEKSPolicy\
    --policy-document file://ebs_policy.json

NODEGROUP_ROLE_NAME=$(aws eks describe-nodegroup --cluster-name $EKS_CLUSTER_NAME --nodegroup-name $EKS_NODE_GROUP_NAME --query "nodegroup.nodeRole" --output text | cut -d'/' -f2-)

aws iam attach-role-policy \
    --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query "Account" --output text):policy/EBSforEKSPolicy \
    --role-name $NODEGROUP_ROLE_NAME

kubectl create ns skills

EBS_ID=$(aws ec2 describe-volumes --filters Name=tag:Name,Values=wsi-ebs --query 'Volumes[*].VolumeId' --output text)

sed -i "s|EBS_ID|$EBS_ID|g" backup.yaml

kubectl apply -f backup.yaml

kubectl get cronjob ebs-snapshot-cronjob -n skills
kubectl get jobs --sort-by=.metadata.creationTimestamp -n skills