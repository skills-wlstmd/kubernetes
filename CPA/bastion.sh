cat << EOF > values.yaml
config:
  ladder:
    nodesToReplicas:
      - [1, 1]
      - [2, 2]
options:
  namespace: default
  target: "deployment/nginx-deployment"
EOF

helm repo add cluster-proportional-autoscaler https://kubernetes-sigs.github.io/cluster-proportional-autoscaler
helm repo update
helm upgrade --install cluster-proportional-autoscaler \
	-f values.yaml \
    cluster-proportional-autoscaler/cluster-proportional-autoscaler

kubectl logs -l  app.kubernetes.io/instance=cluster-proportional-autoscaler