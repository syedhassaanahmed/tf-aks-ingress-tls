#!/bin/bash

CAFE_APP_URL="https://raw.githubusercontent.com/nginxinc/kubernetes-ingress/master/examples/complete-example/cafe.yaml"
NS_NAME="ingress-test-$(uuidgen | head -c 8)"
INGRESS_NAME="cafe-ingress"

export KUBECONFIG=$PWD/kubeconfig

kubectl create ns $NS_NAME
kubectl apply -n $NS_NAME -f $CAFE_APP_URL

kubectl wait -n $NS_NAME --for=condition=ready --timeout=120s pod/$(kubectl get pod -n $NS_NAME -l app=coffee -o jsonpath="{.items[0].metadata.name}")

# Deploy test Ingress
read -r -d '' INGRESS_YAML << EOM
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: $INGRESS_NAME
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/rewrite-target: /\$1
spec:
  tls:
  - hosts:
    - $ingress_fqdn
  rules:
  - host: $ingress_fqdn
    http:
      paths:
      - backend:
          serviceName: coffee-svc
          servicePort: 80
        path: /coffee
EOM

if ! echo "$INGRESS_YAML" | kubectl apply -n $NS_NAME -f -
then
    echo "Unable to deploy Ingress resource into the cluster."
    exit 1
fi

kubectl describe -n $NS_NAME ing/$INGRESS_NAME

curl -k https://$ingress_fqdn/coffee

EXPECTED_VALUE=200
ACTUAL_VALUE=$(curl -k -s -o /dev/null -I -w "%{http_code}" https://$ingress_fqdn/coffee)

kubectl delete ns $NS_NAME

unset KUBECONFIG

if [ "$EXPECTED_VALUE" == "$ACTUAL_VALUE" ]; then
    echo "AKS - Nginx Ingress test passed"
else    
    echo "AKS - Nginx Ingress test failed"
fi
