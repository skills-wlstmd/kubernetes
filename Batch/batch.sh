# ==== ENV ====
EKS_CLUSTER_NAME="skills-eks-cluster"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
JOB_QUEUE=$(aws batch describe-job-queues --query 'jobQueues[0].jobQueueName' --output text)
JOB_DEFINITION=$(aws batch describe-job-definitions --query 'jobDefinitions[0].jobDefinitionName' --output text)
JOB_NAME="skills-batch-eks-job"

eksctl create iamidentitymapping \
    --cluster $EKS_CLUSTER_NAME \
    --arn "arn:aws:iam::$ACCOUNT_ID:role/AWSServiceRoleForBatch" \
    --username batch

# ==== COMPUTE ENVIRONMENT (컴퓨팅 환경) ====
cat <<EOF > ./batch-eks-compute-environment.json
{
  "computeEnvironmentName": "skills-batch-eks-ce",
  "type": "MANAGED",
  "state": "ENABLED",
  "eksConfiguration": {
    "eksClusterArn": "arn:aws:eks:ap-northeast-2:362708816803:cluster/skills-eks-cluster",
    "kubernetesNamespace": "batch"
  },
  "computeResources": {
    "type": "EC2",
    "allocationStrategy": "BEST_FIT_PROGRESSIVE",
    "minvCpus": 0,
    "maxvCpus": 128,
    "instanceTypes": [
        "c5.large"
    ],
    "subnets": [
        "subnet-09b9ef37bb0c33961",
        "subnet-0dc080f81d0456cbe"
    ],
    "securityGroupIds": [
        "sg-0e633a2a9006a4361"
    ],
    "instanceRole": "arn:aws:iam::362708816803:instance-profile/skills-role"
  }
}
EOF

aws batch create-compute-environment --cli-input-json file://./batch-eks-compute-environment.json

# ==== JOB QUEUE (작업 대기열) ====
cat <<EOF > ./batch-eks-job-queue.json
{
  "jobQueueName": "skills-batch-eks-jq",
  "priority": 10,
  "computeEnvironmentOrder": [
    {
      "order": 1,
      "computeEnvironment": "skills-batch-eks-ce"
    }
  ]
}
EOF

aws batch create-job-queue --cli-input-json file://./batch-eks-job-queue.json

# ==== JOB DEFINITION (작업 정의) ====
cat <<EOF > ./batch-eks-jd.json
{
  "jobDefinitionName": "skills-batch-eks-job-definition",
  "type": "container",
  "eksProperties": {
    "podProperties": {
      "hostNetwork": true,
      "containers": [
        {
          "image": "nginx",
          "name": "nginx-container",
          "command": [
            "nginx",
            "-g",
            "daemon off;"
          ],
          "resources": {
            "limits": {
              "cpu": "1",
              "memory": "512Mi"
            },
            "requests": {
              "cpu": "1",
              "memory": "512Mi"
            }
          },
          "env": [],
          "volumeMounts": []
        }
      ],
      "volumes": [],
      "metadata": {
        "labels": {
          "environment": "test"
        }
      }
    }
  }
}
EOF

aws batch register-job-definition --cli-input-json file://batch-eks-jd.json

# ==== JOB SUBMIT (작업) ====
aws batch submit-job --job-queue $JOB_QUEUE \
    --job-definition $JOB_DEFINITION \
    --job-name $JOB_NAME

# Pod 확인
kubectl get po -n batch

