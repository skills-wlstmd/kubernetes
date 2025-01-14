kubectl proxy &
docker run -d -p 8080:8080 --net=host hjacobs/kube-ops-view