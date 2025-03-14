curl -s https://fluxcd.io/install.sh | sudo bash

export GITHUB_USER=wlstmd
export GITHUB_TOKEN=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

flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=fluxcd-repo \
  --branch=main \
  --path=./clusters/skills-eks-cluster \
  --personal

kubectl get pods -n flux-system
kubectl get-all -n flux-system
kubectl get crd | grep fluxc

GITURL="https://github.com/wlstmd/fluxcd-test.git"
flux create source git nginx-example1 \
  --url=$GITURL \
  --branch=main \
  --interval=30s

flux get sources git
kubectl -n flux-system get gitrepositories

flux create kustomization nginx-example1 \
  --target-namespace=default \
  --prune=true \
  --interval=1m \
  --source=nginx-example1 \
  --path="./nginx" \
  --health-check-timeout=2m

kubectl -n default get po,svc

flux get kustomizations
kubectl -n flux-system get kustomizations

# 자동 sync확인
git push origin main

kubectl -n default  describe po nginx-example1 | grep "Image:"

# 삭제
flux delete kustomization nginx-example1
kubectl -n default get po,svc
flux -n default delete source git nginx-example1

# flux 삭제
flux uninstall --namespace=flux-system

# HELM
flux create helmrelease helm-application-example \
  --chart hello-world \
  --source HelmRepository/helm-source-example \
  --chart-version "0.1.0" \
  --namespace default

kubectl get HelmRelease -n default
flux get HelmRelease -n default
helm -n default ls

cat <<EOF > dev-values.yaml
replicaCount: 2
EOF

flux create helmrelease helm-application-example \
  --chart hello-world \
  --source HelmRepository/helm-source-example \
  --chart-version "0.1.0" \
  --namespace default \
  --values values.yaml

helm -n default ls # 리비전 증가


kubectl -n default describe helmrelease helm-application-example | grep "Revision:"

cat <<EOF | kubectl apply -f -
kind: ConfigMap
apiVersion: v1
metadata:
  name: override-value
  namespace: default
data:
  values.yaml: |-
    replicaCount: 3
EOF

flux create helmrelease helm-application-example \
  --chart hello-world \
  --source HelmRepository/helm-source-example \
  --chart-version "0.1.0" \
  --namespace default \
  --values-from=Configmap/override-value

kubectl -n default describe helmrelease helm-application-example # 리비전 증가

kubectl -n default get po

# 삭제
flux -n default delete helmrelease helm-application-example
flux -n defualt delete source helm helm-source-example
flux uninstall --namespace=flux-system

# 대시보드
curl --silent --location "https://github.com/weaveworks/weave-gitops/releases/download/v0.24.0/gitops-$(uname)-$(uname -m).tar.gz" | tar xz -C /tmp
sudo mv /tmp/gitops /usr/local/bin
gitops version

PASSWORD="password"
gitops create dashboard ww-gitops \
  --password=$PASSWORD

flux -n flux-system get helmrelease

kubectl -n flux-system get pod

kubectl port-forward svc/ww-gitops-weave-gitops -n flux-system 9001:9001 --address 0.0.0.0