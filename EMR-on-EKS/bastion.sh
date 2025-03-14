export CLUSTER_NAME="skills-eks-cluster"
export S3_BUCKET_NAME="skills-emr-on-eks"
export REGION=ap-northeast-2
export ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export CLUSTER_OIDC=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -c 9-100)

kubectl create ns emr

eksctl create iamidentitymapping --cluster $CLUSTER_NAME \
    --namespace emr \
    --service-name "emr-containers" \
    --region $REGION

eksctl utils associate-iam-oidc-provider \
   --cluster $CLUSTER_NAME \
   --region $REGION \
   --approve

cat << EOF > emr-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/$CLUSTER_OIDC"
            },
            "Action": "sts:AssumeRoleWithWebIdentity"
        }
    ]
}
EOF

aws iam create-role \
  --role-name EMRContainers-JobExecutionRole \
  --assume-role-policy-document file://emr-trust-policy.json

cat << EOF > emr-container-jobexecutionrole.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:PutLogEvents",
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:aws:logs:*:*:*"
      ]
    }
  ]
} 
EOF

aws iam put-role-policy \
  --role-name EMRContainers-JobExecutionRole \
  --policy-name EMR-Containers-Job-Execution \
  --policy-document file://emr-container-jobexecutionrole.json

aws emr-containers create-virtual-cluster --name skills-emr-cluster --container-provider '{
   "id": "'"$CLUSTER_NAME"'",
   "type": "EKS",
   "info": {
      "eksInfo": {
         "namespace": "emr"
      }
   }
}'

aws s3 mb s3://$S3_BUCKET_NAME

S3_PREFIX="s3://$S3_BUCKET_NAME"
V_C_ID=$(aws emr-containers list-virtual-clusters --query "virtualClusters[?name=='skills-emr-cluster'].id" --output text)
EMR_ROLE_ARN=$(aws iam get-role --role-name EMRContainers-JobExecutionRole --query Role.Arn --output text)

cat << EOF > job-app.py
from pyspark.sql import SparkSession
from pyspark import SparkContext
from pyspark.sql import functions as F
from pyspark.sql import types as T
from pyspark.sql import Row
import argparse

spark = SparkSession.builder.appName("sample_script").getOrCreate()

def main():
    df_spark = spark.createDataFrame([
        Row(a=1, b=11.2, c='apple'),
        Row(a=2, b=3.5, c='banana'),
        Row(a=3, b=7.3, c='tomato'),
    ])

    df_spark.write.mode('overwrite').parquet('s3://$S3_BUCKET_NAME/result/job-without-app/')

if __name__ == "__main__":
    main()
EOF

aws s3 cp job-app.py s3://$S3_BUCKET_NAME/spark-src/job-app.py

cat << EOF > request.json
{
    "name": "wsi-emr-stark-job",
    "virtualClusterId": "${V_C_ID}",
    "executionRoleArn": "${EMR_ROLE_ARN}",
    "releaseLabel": "emr-6.4.0-latest",
    "jobDriver": {
        "sparkSubmitJobDriver": {
            "entryPoint": "s3://$S3_BUCKET_NAME/spark-src/job-app.py",
            "sparkSubmitParameters": "--conf spark.executor.instances=1 --conf spark.executor.memory=1G --conf spark.executor.cores=1 --conf spark.driver.cores=1"
        }
    },
    "configurationOverrides": {
        "applicationConfiguration": [
            {
                "classification": "spark-defaults",
                "properties": {
                  "spark.dynamicAllocation.enabled": "false",
                  "spark.kubernetes.executor.deleteOnTermination": "true"
                }
            }
        ],
        "monitoringConfiguration": {
            "cloudWatchMonitoringConfiguration": {
                "logGroupName": "/emr-on-eks/${CLUSTER_NAME}",
                "logStreamNamePrefix": "emr"
            },
            "s3MonitoringConfiguration": {
                "logUri": "${S3_PREFIX}/"
            }
        }
    }
}
EOF

aws logs create-log-group --log-group-name=/emr-on-eks/$CLUSTER_NAME

aws emr-containers start-job-run --cli-input-json file://request.json

export EMR_CONATINER_CLIENT_SA=$(kubectl get sa -n emr -o json | jq -r '.items[].metadata.name | select(startswith("emr-containers-sa-spark-client"))')
export EMR_CONATINER_DRIVER_SA=$(kubectl get sa -n emr -o json | jq -r '.items[].metadata.name | select(startswith("emr-containers-sa-spark-driver"))')
export EMR_CONATINER_EXECUTOR_SA=$(kubectl get sa -n emr -o json | jq -r '.items[].metadata.name | select(startswith("emr-containers-sa-spark-executor"))')
export NAMESPACE=emr

cat << EOF > emr-trust-policy-release.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/$CLUSTER_OIDC"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "$CLUSTER_OIDC:aud": "sts.amazonaws.com",
                    "$CLUSTER_OIDC:sub": [
                        "system:serviceaccount:$NAMESPACE:$EMR_CONATINER_CLIENT_SA",
                        "system:serviceaccount:$NAMESPACE:$EMR_CONATINER_DRIVER_SA",
                        "system:serviceaccount:$NAMESPACE:$EMR_CONATINER_EXECUTOR_SA"
                    ]
                }
            }
        }
    ]
}
EOF

aws iam update-assume-role-policy \
  --role-name EMRContainers-JobExecutionRole \
  --policy-document file://emr-trust-policy-release.json

aws emr-containers start-job-run --cli-input-json file://request.json