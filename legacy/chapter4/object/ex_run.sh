#!/bin/bash

EX_ID=$1
BRANCH=$2
RET=0

if [ -z $EX_ID ]; then
  echo "please set exam id!"
  RET=1
  exit ${RET}
fi

if [ -z $BRANCH ]; then
  echo "please set branch!"
  RET=1
  exit ${RET}
fi


if [ $EX_ID == "ex1" ]; then
  echo "set ex1 objects!"
  kubectl apply -f https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/$BRANCH/chapter4/object/ex1.yaml
  exit ${RET}
fi

if [ $EX_ID == "ex2" ]; then
  echo "set ex2 objects!"
  kubectl delete -f https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/$BRANCH/chapter4/object/ex1.yaml
  kubectl apply -f https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/$BRANCH/chapter4/object/ex2.yaml
  exit ${RET}
fi

if [ $EX_ID == "delete" ]; then
  echo "delete objects!"
  kubectl delete -f https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/$BRANCH/chapter4/object/ex1.yaml
  kubectl delete -f https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/$BRANCH/chapter4/object/ex2.yaml
  exit ${RET}
fi

echo "Please check ID"

exit ${RET}
