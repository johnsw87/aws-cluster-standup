#!/bin/bash
kubectl apply -f gateway.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
watch kubectl get ingress nginx
