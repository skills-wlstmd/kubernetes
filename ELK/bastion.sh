# Environment variables
export EKS_CLUSTER_NAME=skills-eks-cluster
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=ap-northeast-2
export ES_DOMAIN_NAME="skills-logging"
export ES_VERSION="7.10"
export ES_DOMAIN_USER="admin"
export ES_DOMAIN_PASSWORD="$(openssl rand -base64 12)_Ek1$"

# Create OIDC provider for EKS
eksctl utils associate-iam-oidc-provider \
    --cluster $EKS_CLUSTER_NAME \
    --approve

# Add AWS Load Balancer Controller Helm 
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Create IAM policy for Logstash
cat << EOF > logstash-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "es:ESHttp*"
            ],
            "Resource": "arn:aws:es:${AWS_REGION}:${ACCOUNT_ID}:domain/${ES_DOMAIN_NAME}"
        }
    ]
}
EOF

# Create IAM policy
aws iam create-policy \
    --policy-name logstash-policy \
    --policy-document file://logstash-policy.json

# Create namespace and service account
kubectl create namespace logging

eksctl create iamserviceaccount \
    --name logstash \
    --namespace logging \
    --cluster $EKS_CLUSTER_NAME \
    --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/logstash-policy" \
    --override-existing-serviceaccounts \
    --approve

# Verify service account
kubectl -n logging describe serviceaccounts logstash

# Create Elasticsearch domain
cat << EOF > es_domain.json
{
    "DomainName": "${ES_DOMAIN_NAME}",
    "ElasticsearchVersion": "${ES_VERSION}",
    "ElasticsearchClusterConfig": {
        "InstanceType": "r5.large.elasticsearch",
        "InstanceCount": 1,
        "DedicatedMasterEnabled": false,
        "ZoneAwarenessEnabled": false,
        "WarmEnabled": false
    },
    "EBSOptions": {
        "EBSEnabled": true,
        "VolumeType": "gp2",
        "VolumeSize": 100
    },
    "AccessPolicies": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"*\"},\"Action\":\"es:ESHttp*\",\"Resource\":\"arn:aws:es:${AWS_REGION}:${ACCOUNT_ID}:domain/${ES_DOMAIN_NAME}/*\"}]}",
    "SnapshotOptions": {},
    "CognitoOptions": {
        "Enabled": false
    },
    "EncryptionAtRestOptions": {
        "Enabled": true
    },
    "NodeToNodeEncryptionOptions": {
        "Enabled": true
    },
    "DomainEndpointOptions": {
        "EnforceHTTPS": true,
        "TLSSecurityPolicy": "Policy-Min-TLS-1-0-2019-07"
    },
    "AdvancedSecurityOptions": {
        "Enabled": true,
        "InternalUserDatabaseEnabled": true,
        "MasterUserOptions": {
            "MasterUserName": "${ES_DOMAIN_USER}",
            "MasterUserPassword": "${ES_DOMAIN_PASSWORD}"
        }
    }
}
EOF

# Create Elasticsearch domain
aws es create-elasticsearch-domain \
    --cli-input-json file://es_domain.json

# Get necessary variables
export LOGSTASH_ROLE=$(eksctl get iamserviceaccount --cluster $EKS_CLUSTER_NAME --namespace logging -o json | jq '.[].status.roleARN' -r)
export ES_ENDPOINT=$(aws es describe-elasticsearch-domain --domain-name ${ES_DOMAIN_NAME} --output text --query "DomainStatus.Endpoint")

# Update Elasticsearch security settings
curl -sS -u "${ES_DOMAIN_USER}:${ES_DOMAIN_PASSWORD}" \
    -X PATCH \
    https://${ES_ENDPOINT}/_opendistro/_security/api/rolesmapping/all_access?pretty \
    -H 'Content-Type: application/json' \
    -d'
[
  {
    "op": "add", "path": "/backend_roles", "value": ["'${LOGSTASH_ROLE}'"]
  }
]
'

EKS_NODE_GROUP_SG_ID=$(aws ec2 describe-instances --filter Name=tag:Name,Values=skills-app-node --query "Reservations[1].Instances[].SecurityGroups[].GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id $EKS_NODE_GROUP_SG_ID --protocol tcp --port 5044 --source-group $EKS_NODE_GROUP_SG_ID
aws ec2 authorize-security-group-ingress --group-id $EKS_NODE_GROUP_SG_ID --protocol tcp --port 5000 --source-group $EKS_NODE_GROUP_SG_ID
aws ec2 authorize-security-group-egress --group-id $EKS_NODE_GROUP_SG_ID --protocol tcp --port 5044 --source-group $EKS_NODE_GROUP_SG_ID
aws ec2 authorize-security-group-egress --group-id $EKS_NODE_GROUP_SG_ID --protocol tcp --port 5000 --source-group $EKS_NODE_GROUP_SG_ID

# Create Logstash ConfigMap
cat << EOF > logstash-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: logstash-config
  namespace: logging
data:
  logstash.yml: |
    http.host: "0.0.0.0"
    path.config: /usr/share/logstash/pipeline
  logstash.conf: |
    input {
      beats {
        port => 5044
      }
    }
    
    filter {
      grok {
        match => { "message" => "%{COMBINEDAPACHELOG}" }
      }
      date {
        match => [ "timestamp" , "dd/MMM/yyyy:HH:mm:ss Z" ]
      }
    }
    
    output {
      elasticsearch {
        hosts => ["https://${ES_ENDPOINT}:443"]
        ssl => true
        user => "${ES_DOMAIN_USER}"
        password => "${ES_DOMAIN_PASSWORD}"
        index => "logstash-%{+YYYY.MM.dd}"
        ilm_enabled => false
      }
    }
EOF

# Apply Logstash ConfigMap
kubectl apply -f logstash-config.yaml

# Create Logstash Deployment
cat << EOF > logstash-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logstash
  namespace: logging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: logstash
  template:
    metadata:
      labels:
        app: logstash
    spec:
      serviceAccountName: logstash
      containers:
      - name: logstash
        image: docker.elastic.co/logstash/logstash:7.10.2
        ports:
        - containerPort: 5044
        volumeMounts:
        - name: config-volume
          mountPath: /usr/share/logstash/config
        - name: pipeline-volume
          mountPath: /usr/share/logstash/pipeline
      volumes:
      - name: config-volume
        configMap:
          name: logstash-config
          items:
            - key: logstash.yml
              path: logstash.yml
      - name: pipeline-volume
        configMap:
          name: logstash-config
          items:
            - key: logstash.conf
              path: logstash.conf
---
apiVersion: v1
kind: Service
metadata:
  name: logstash
  namespace: logging
spec:
  type: ClusterIP
  ports:
  - port: 5044
    targetPort: 5044
    protocol: TCP
  selector:
    app: logstash
EOF

# Apply Logstash deployment
kubectl apply -f logstash-deployment.yaml

# Check deployment status
kubectl -n logging get pods -o wide


cat << EOF > demo-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  namespace: logging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
      - name: demo-app
        image: nginx:latest
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-logs
          mountPath: /var/log/nginx
      - name: filebeat
        image: docker.elastic.co/beats/filebeat:7.10.2
        volumeMounts:
        - name: nginx-logs
          mountPath: /var/log/nginx
        - name: filebeat-config
          mountPath: /usr/share/filebeat/filebeat.yml
          subPath: filebeat.yml
      volumes:
      - name: nginx-logs
        emptyDir: {}
      - name: filebeat-config
        configMap:
          name: filebeat-config
          items:
            - key: filebeat.yml
              path: filebeat.yml
---
apiVersion: v1
kind: Service
metadata:
  name: demo-app
  namespace: logging
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: demo-app
---
EOF
kubectl apply -f demo-app.yaml

cat << EOF > filebeat-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-config
  namespace: logging
data:
  filebeat.yml: |
    filebeat.inputs:
    - type: log
      enabled: true
      paths:
        - /var/log/nginx/access.log
      fields:
        app: demo-app
        type: nginx-access
      fields_under_root: true

    - type: log
      enabled: true
      paths:
        - /var/log/nginx/error.log
      fields:
        app: demo-app
        type: nginx-error
      fields_under_root: true

    output.logstash:
      hosts: ["logstash.logging.svc.cluster.local:5044"]

    logging.json: true
    logging.metrics.enabled: false
---
EOF
kubectl apply -f filebeat-config.yaml

cat << EOF > nginx-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: logging
data:
  nginx.conf: |
    user  nginx;
    worker_processes  1;

    error_log  /var/log/nginx/error.log warn;
    pid        /var/run/nginx.pid;

    events {
        worker_connections  1024;
    }

    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;

        log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                         '$status $body_bytes_sent "$http_referer" '
                         '"$http_user_agent" "$http_x_forwarded_for"';

        access_log  /var/log/nginx/access.log  main;

        sendfile        on;
        keepalive_timeout  65;

        server {
            listen       80;
            server_name  localhost;

            location / {
                root   /usr/share/nginx/html;
                index  index.html index.htm;
            }

            location /error {
                return 500;
            }
        }
    }
EOF
kubectl apply -f nginx-config.yaml

# 서비스 IP 확인
export SERVICE_IP=$(kubectl -n logging get svc demo-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# 일반 접속 로그 생성
curl http://$SERVICE_IP/

# 에러 로그 생성
curl http://$SERVICE_IP/error

# Print access information
echo "Kibana URL: https://${ES_ENDPOINT}/_plugin/kibana/"
echo "Kibana user: ${ES_DOMAIN_USER}"
echo "Kibana password: ${ES_DOMAIN_PASSWORD}"
