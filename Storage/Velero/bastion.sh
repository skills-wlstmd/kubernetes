export BUCKET_NAME="skills-velero"
export REGION_CODE=ap-northeast-2
export BACKUP_NAME="skills-backup"

aws s3 mb s3://$BUCKET_NAME --region $REGION_CODE

aws iam create-user --user-name velero

cat << EOF > velero-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:PutObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}"
            ]
        }
    ]
}
EOF

aws iam put-user-policy \
  --user-name velero \
  --policy-name velero \
  --policy-document file://velero-policy.json

aws iam create-access-key --user-name velero

wget https://github.com/vmware-tanzu/velero/releases/download/v1.15.2/velero-v1.15.2-linux-amd64.tar.gz
tar zxvf velero-v1.15.2-linux-amd64.tar.gz
sudo cp velero-v1.15.2-linux-amd64/velero /usr/local/bin/

cat << EOF > credentials-velero
[default]
aws_access_key_id=<AWS_ACCESS_KEY_ID>
aws_secret_access_key=<AWS_SECRET_ACCESS_KEY>
EOF

velero install \
    --provider aws \
    --bucket $BUCKET_NAME \
    --secret-file ./credentials-velero \
    --backup-location-config region=$REGION_CODE \
    --use-volume-snapshots=false \
    --plugins velero/velero-plugin-for-aws:v1.10.0

velero backup create $BACKUP_NAME --include-namespaces skills --wait

velero get backup

velero restore create --from-backup $BACKUP_NAME --wait