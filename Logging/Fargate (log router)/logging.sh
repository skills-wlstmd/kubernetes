# ENV
EKS_CLUSTER_NAME="<CLUSTER_NAME>"
EKS_NODE_GROUP_NAME="<NODE_GROUP_NAME>"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
REGION_CODE=$(aws configure get default.region --output text)

# Namespace
kubectl apply -f aws-observability-namespace.yaml

# OIDC
eksctl utils associate-iam-oidc-provider --region=$REGION_CODE --cluster=$EKS_CLUSTER_NAME --approve

# IAM Role Attach Policy
curl -o permissions.json https://raw.githubusercontent.com/aws-samples/amazon-eks-fluent-logging-examples/mainline/examples/fargate/cloudwatchlogs/permissions.json
FARGATE_POLICY_ARN=$(aws --region "$REGION_CODE" --query Policy.Arn --output text iam create-policy --policy-name fargate-policy --policy-document file://permissions.json)
FARGATE_ROLE_NAME=$(aws iam list-roles --query "Roles[?contains(RoleName, 'eksctl-$EKS_CLUSTER_NAME-c-FargatePodExecutionRole')].RoleName" --output text)
NODE_GROUP=$(aws iam get-role --role-name $FARGATE_ROLE_NAME --query "Role.RoleName" --output text)
NODE_GROUP_ROLE_NAME=$(aws eks describe-nodegroup --cluster-name $EKS_CLUSTER_NAME --nodegroup-name $EKS_NODE_GROUP_NAME --query 'nodegroup.nodeRole' --output text | awk -F/ '{print $NF}')

# eksctl list roles check
aws iam list-roles | grep 'eksctl-'

aws iam attach-role-policy --policy-arn $FARGATE_POLICY_ARN --role-name $NODE_GROUP
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess --role-name $NODE_GROUP_ROLE_NAME

# ConfigMap
kubectl apply -f aws-logging-cloudwatch-configmap.yaml

# Add Log & Check Log
kubectl exec -it -n skills deployment.apps/skills-app-deployment -- curl localhost:8080/healthcheck > /dev/null 2>&1
kubectl logs -n skills deployment.apps/skills-app-deployment -c skills-app