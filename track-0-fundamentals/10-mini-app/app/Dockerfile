# Multi-stage build: ビルド用と実行用を分けて軽量化
FROM python:3.12-slim AS build

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


FROM python:3.12-slim

# 非 root ユーザで動かす (PSA restricted でも通る最小構成)
RUN useradd --create-home --uid 10001 app
WORKDIR /app

COPY --from=build /install /usr/local
COPY main.py .

USER 10001
EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
