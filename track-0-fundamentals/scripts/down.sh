#!/usr/bin/env bash
# kind クラスタ 'bootcamp' を消す。データも一緒に消えるので注意。
set -euo pipefail

if kind get clusters 2>/dev/null | grep -qx bootcamp; then
  echo "==> kind delete cluster --name bootcamp"
  kind delete cluster --name bootcamp
  echo "done."
else
  echo "クラスタ 'bootcamp' は存在しません。"
fi
