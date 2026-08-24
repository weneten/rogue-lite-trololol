#!/usr/bin/env python3
"""Nightbane lobby relay: host gets a 4-letter code, others join, messages fan out."""

from __future__ import annotations

import asyncio
import json
import random
import time

import websockets

ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
MAX_PLAYERS = 4
ROOM_TTL = 45 * 60

rooms: dict[str, dict] = {}


def _code() -> str:
    for _ in range(32):
        c = "".join(random.choice(ALPHABET) for _ in range(4))
        if c not in rooms:
            return c
    return "".join(random.choice(ALPHABET) for _ in range(5))


def _purge() -> None:
    now = time.time()
    dead = [k for k, r in rooms.items() if now - r["born"] > ROOM_TTL]
    for k in dead:
        rooms.pop(k, None)


async def _send(ws, payload: dict) -> None:
    try:
        await ws.send(json.dumps(payload, separators=(",", ":")))
    except Exception:
        pass


async def _broadcast(room: dict, payload: dict, skip=None) -> None:
    dead = []
    for pid, ws in list(room["peers"].items()):
        if ws is skip:
            continue
        try:
            await ws.send(json.dumps(payload, separators=(",", ":")))
        except Exception:
            dead.append(pid)
    for pid in dead:
        room["peers"].pop(pid, None)
        room["meta"].pop(pid, None)


def _roster(room: dict) -> dict:
    players = []
    for pid, meta in room["meta"].items():
        players.append({"pid": pid, "char": meta.get("char", ""), "host": pid == room["host_id"]})
    return {"op": "roster", "code": room["code"], "players": players}


async def handler(ws):
    _purge()
    pid = None
    room = None
    try:
        async for raw in ws:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await _send(ws, {"op": "err", "msg": "bad json"})
                continue
            op = msg.get("op")
            if op == "host":
                if room is not None:
                    continue
                code = _code()
                pid = 1
                room = {
                    "code": code,
                    "born": time.time(),
                    "host_id": 1,
                    "next_id": 2,
                    "peers": {1: ws},
                    "meta": {1: {"char": str(msg.get("char", ""))}},
                    "started": False,
                }
                rooms[code] = room
                await _send(ws, {"op": "welcome", "code": code, "pid": pid, "host": True})
                await _broadcast(room, _roster(room))
            elif op == "join":
                if room is not None:
                    continue
                code = str(msg.get("code", "")).upper().strip()
                target = rooms.get(code)
                if target is None or target["started"]:
                    await _send(ws, {"op": "err", "msg": "no lobby"})
                    continue
                if len(target["peers"]) >= MAX_PLAYERS:
                    await _send(ws, {"op": "err", "msg": "full"})
                    continue
                pid = target["next_id"]
                target["next_id"] += 1
                target["peers"][pid] = ws
                target["meta"][pid] = {"char": str(msg.get("char", ""))}
                room = target
                await _send(ws, {"op": "welcome", "code": code, "pid": pid, "host": False})
                await _broadcast(room, _roster(room))
            elif op == "start":
                if room is None or pid != room["host_id"]:
                    continue
                room["started"] = True
                seed = int(msg.get("seed") or random.randint(1, 2_000_000_000))
                await _broadcast(room, {"op": "start", "seed": seed, "players": _roster(room)["players"]})
            elif room is not None:
                msg["from"] = pid
                await _broadcast(room, msg, skip=ws)
    finally:
        if room is not None and pid is not None:
            room["peers"].pop(pid, None)
            room["meta"].pop(pid, None)
            if pid == room["host_id"] or not room["peers"]:
                rooms.pop(room["code"], None)
                await _broadcast(room, {"op": "closed"})
            else:
                await _broadcast(room, _roster(room))


async def main() -> None:
    async with websockets.serve(handler, "0.0.0.0", 8765, max_size=2**18, origins=None):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
