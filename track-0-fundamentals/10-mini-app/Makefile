# mini-app の build / load / deploy / 動作確認をまとめた Makefile。
# Track 0 のゴール感を 1 コマンドで体験できるようにする。

CLUSTER ?= bootcamp
IMAGE   ?= mini-ap:0.1
NS      ?= mini-app

.PHONY: help build load deploy up smoke logs delete down

help:
	@echo "make build   - app を docker build"
	@echo "make load    - build した image を kind cluster に load"
	@echo "make deploy  - manifests/ を apply"
	@echo "make up      - build + load + deploy + wait (= 全部)"
	@echo "make smoke   - curl で動作確認"
	@echo "make logs    - 各層の log を tail"
	@echo "make delete  - namespace mini-app を消す"

build:
	docker build -t $(IMAGE) app/

load:
	kind load docker-image $(IMAGE) --name $(CLUSTER)

deploy:
	kubectl apply -f manifests/
	kubectl -n $(NS) wait --for=condition=Ready pods --all --timeout=180s

up: build load deploy

# jq があれば pretty-print。無ければそのまま出す。
PRETTY := $(shell command -v jq >/dev/null 2>&1 && echo jq || echo cat)

smoke:
	@echo "==> GET /"
	@curl -s -H 'Host: app.local' http://localhost/ | $(PRETTY)
	@echo ""
	@echo "==> POST /guestbook"
	@curl -s -H 'Host: app.local' -H 'Content-Type: application/json' \
	  -d '{"name":"alice","msg":"hello from k8s!"}' \
	  http://localhost/guestbook | $(PRETTY)
	@echo ""
	@echo "==> GET /guestbook"
	@curl -s -H 'Host: app.local' http://localhost/guestbook | $(PRETTY)

logs:
	@echo "== db =="
	kubectl -n $(NS) logs -l app=db --tail=5
	@echo "== ap =="
	kubectl -n $(NS) logs -l app=ap --tail=5
	@echo "== web =="
	kubectl -n $(NS) logs -l app=web --tail=5

delete:
	kubectl delete ns $(NS)

down: delete
