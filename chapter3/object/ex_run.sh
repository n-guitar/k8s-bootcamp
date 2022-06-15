#!/bin/sh

EX_ID=$1
RET=0

if [ -z $EX_ID ]; then
  echo "please set exam id!"
  RET=1
  exit ${RET}
fi


if [ $EX_ID == "ex2" ]; then
  echo "set ex2 objects!"
  exit ${RET}
fi

echo "Please check ID"

exit ${RET}
