#!/usr/bin/env bash
#set -o errexit

NEWLINE=$'\n'

#clear

kubectl apply -f 0-ns.yaml

echo "${NEWLINE}"

echo ">>> 1. Good config..."
kubectl apply -f 1-ok.yaml
sleep 2
kubectl delete -f 1-ok.yaml
sleep 2

echo "${NEWLINE}"

echo ">>> 2. Deployment - Missing container security context element..."
kubectl apply -f 2-dep-sec-cont.yaml
sleep 2

echo "${NEWLINE}"

echo ">>> 3. Pod - Missing container security context element..."
kubectl apply -f 3-pod.yaml
sleep 2

echo "${NEWLINE}"

echo ">>> 4. Pod - Pod security context, but Missing container security context element..."
kubectl apply -f 4-pod.yaml
sleep 2

echo "${NEWLINE}"

echo ">>> 5. Pod - Container security context element present, with incorrect settings..."
kubectl apply -f 5-pod.yaml
sleep 2

echo "${NEWLINE}"

echo ">>> 6. Pod - Container security context element present, with incorrect spec.hostNetwork, spec.hostPID, spec.hostIPC settings..."
kubectl apply -f 6-pod.yaml
sleep 2

echo "${NEWLINE}"