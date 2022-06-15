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


if [ $EX_ID == "ex2" ]; then
  echo "set ex2 objects!"
  kubectl apply -f https://raw.githubusercontent.com/n-guitar/k8s-bootcamp/$BRANCH/chapter3/object/ex2-pod.yaml
  exit ${RET}
fi

echo "Please check ID"

exit ${RET}
