"""mini-app AP: FastAPI + Postgres.

楽しさのために 4 つのエンドポイントを用意:
  GET  /           -> 起動メッセージ + DB 現在時刻 + 自分の pod 名
  GET  /healthz    -> readiness/liveness 用
  GET  /guestbook  -> ゲストブック一覧
  POST /guestbook  -> {"name": "...", "msg": "..."} を追加

ConfigMap (MESSAGE / LOG_LEVEL) と Secret (DB_PASSWORD) を環境変数で受け取る。
DB ホスト/ユーザ/DB 名はサービス DNS のため固定で問題ないが、env で上書き可能にしてある。
"""
from __future__ import annotations

import os
import socket
from contextlib import asynccontextmanager
from datetime import datetime

import asyncpg
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel


DB_HOST = os.environ.get("DB_HOST", "db.mini-app.svc.cluster.local")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "app")
DB_USER = os.environ.get("DB_USER", "app")
DB_PASSWORD = os.environ["DB_PASSWORD"]  # Secret から注入されることを期待
MESSAGE = os.environ.get("MESSAGE", "hello from FastAPI")


@asynccontextmanager
async def lifespan(app: FastAPI):
    pool = await asyncpg.create_pool(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        min_size=1,
        max_size=5,
    )
    async with pool.acquire() as conn:
        await conn.execute(
            """
            CREATE TABLE IF NOT EXISTS guestbook (
              id     SERIAL PRIMARY KEY,
              name   TEXT NOT NULL,
              msg    TEXT NOT NULL,
              ts     TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """
        )
    app.state.pool = pool
    yield
    await pool.close()


app = FastAPI(lifespan=lifespan)


class Entry(BaseModel):
    name: str
    msg: str


@app.get("/")
async def root():
    async with app.state.pool.acquire() as conn:
        now: datetime = await conn.fetchval("SELECT now()")
    return {
        "message": MESSAGE,
        "pod": socket.gethostname(),
        "db_now": now.isoformat(),
    }


@app.get("/healthz")
async def healthz():
    try:
        async with app.state.pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"db not ready: {e}") from e
    return {"ok": True}


@app.get("/guestbook")
async def list_entries():
    async with app.state.pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT id, name, msg, ts FROM guestbook ORDER BY id DESC LIMIT 50"
        )
    return [
        {"id": r["id"], "name": r["name"], "msg": r["msg"], "ts": r["ts"].isoformat()}
        for r in rows
    ]


@app.post("/guestbook")
async def add_entry(entry: Entry):
    async with app.state.pool.acquire() as conn:
        new_id = await conn.fetchval(
            "INSERT INTO guestbook (name, msg) VALUES ($1, $2) RETURNING id",
            entry.name,
            entry.msg,
        )
    return {"id": new_id}
