#!/usr/bin/env python3
"""Yamaha AV レシーバー（YXC ＋ 旧 XML API の YNC）のふりをする開発用のサーバー。

実機がなくても Yamaha 対応の通信処理を試すためのもの。RX-V581 に近い応答を返す（値は公開仕様の例から作った想定）。
状態は操作に合わせて変わり、受け取ったリクエストは標準出力に 1 行ずつ出す。

使い方:
  python3 scripts/mock-yamaha.py                 # 0.0.0.0:80 で待ち受け
  PORT=8081 python3 scripts/mock-yamaha.py
  MODERN=1 python3 scripts/mock-yamaha.py        # 2020 年以降の機種のふり（controlCursor / actual_volume あり、YNC なし）
"""
import json
import os
import re
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

MODERN = os.environ.get("MODERN") == "1"

# 状態変化の通知（UDP）の送り先。リクエストの X-AppPort ヘッダーで登録される（実機は 10 分で切れる）
event_targets = {}


def send_event(payload):
    data = json.dumps(payload).encode()
    for (ip, port) in list(event_targets.items()):
        socket.socket(socket.AF_INET, socket.SOCK_DGRAM).sendto(data, (ip, port))
        print("EVENT ->", ip, port, payload, flush=True)

state = {
    "main": {"power": "on", "volume": 97, "mute": False, "input": "hdmi1",
             "sound_program": "straight", "pure_direct": False},
    "zone2": {"power": "standby", "volume": 60, "mute": False, "input": "tuner"},
    "tuner": {"band": "fm", "fm": {"preset": 1, "freq": 80000}, "am": {"preset": 0, "freq": 594}},
}
presets = [{"band": "fm", "number": f} for f in (80000, 81300, 82500, 76100)] + \
          [{"band": "am", "number": 594}] + [{"band": "unknown", "number": 0}] * 35


def db(step):
    return -80.5 + step * 0.5


def features():
    main_funcs = ["power", "sleep", "volume", "mute", "sound_program", "direct", "pure_direct",
                  "enhancer", "tone_control", "signal_info"]
    ranges = [{"id": "volume", "min": 0, "max": 161, "step": 1}]
    if MODERN:
        main_funcs += ["cursor", "menu", "actual_volume"]
        ranges.append({"id": "actual_volume_db", "min": -80.5, "max": 16.5, "step": 0.5})
    inputs = ["hdmi1", "hdmi2", "hdmi3", "hdmi4", "av1", "av2", "audio1", "audio2", "tuner",
              "usb", "bluetooth", "server", "net_radio", "airplay", "spotify", "mc_link"]
    return {
        "response_code": 0,
        "system": {"func_list": ["wired_lan", "wireless_lan", "network_standby"], "zone_num": 2,
                   "input_list": [{"id": i} for i in inputs]},
        "zone": [
            {"id": "main", "func_list": main_funcs, "input_list": inputs,
             "sound_program_list": ["munich", "vienna", "chamber", "cellar_club", "roxy_theatre",
                                    "sports", "action_game", "roleplaying_game", "music_video",
                                    "standard", "spectacle", "sci-fi", "adventure", "drama",
                                    "mono_movie", "2ch_stereo", "7ch_stereo", "surr_decoder", "straight"],
             "range_step": ranges},
            {"id": "zone2", "func_list": ["power", "volume", "mute"], "input_list": inputs,
             "range_step": [{"id": "volume", "min": 0, "max": 161, "step": 1}]},
        ],
        "tuner": {"func_list": ["am", "fm"], "preset": {"type": "common", "num": 40}},
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *args):
        pass

    def reply(self, status, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def ok(self, **extra):
        self.reply(200, json.dumps({"response_code": 0, **extra}))

    def do_GET(self):
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        path = url.path
        print(self.client_address[0], "GET", self.path, flush=True)
        if self.headers.get("X-AppPort"):
            event_targets[self.client_address[0]] = int(self.headers["X-AppPort"])
        # 本体や付属リモコンでの操作の真似: /debug/remote?volume=90 / mute=true / input=hdmi2
        if path == "/debug/remote":
            z = state["main"]
            if "volume" in q: z["volume"] = int(q["volume"])
            if "mute" in q: z["mute"] = q["mute"] == "true"
            if "input" in q: z["input"] = q["input"]
            send_event({"main": {k: z[k] for k in ("power", "input", "volume", "mute")}, "device_id": "00A0DEAABBCC"})
            return self.reply(200, "ok", "text/plain")
        if path == "/YamahaRemoteControl/desc.xml" and not MODERN:
            return self.reply(200, '<?xml version="1.0"?><Unit_Description Version="1.0">'
                              '<Cmd_List><Define ID="P1">Main_Zone,Cursor_Control,Cursor</Define>'
                              '<Define ID="P2">Main_Zone,Cursor_Control,Menu_Control</Define></Cmd_List>'
                              '</Unit_Description>', "text/xml")
        m = re.match(r"^/YamahaExtendedControl/v1/(\w+)/(\w+)$", path)
        if not m:
            return self.reply(404, "not found", "text/plain")
        group, method = m.groups()
        if group == "system":
            if method == "getDeviceInfo":
                return self.ok(model_name="RX-V581", destination="J", device_id="00A0DEAABBCC",
                               system_version=2.53, api_version=1.19, netmodule_version="1580")
            if method == "getNetworkStatus":
                return self.ok(network_name="RX-V581 Living", connection="wired_lan",
                               mac_address={"wired_lan": "00A0DEAABBCC", "wireless_lan": "00A0DEAABBCD"})
            if method == "getFeatures":
                return self.reply(200, json.dumps(features()))
            if method == "getNameText":
                return self.ok(input_list=[{"id": "hdmi1", "text": "Blu-ray"}, {"id": "hdmi2", "text": "Apple TV"}],
                               sound_program_list=[])
        if group in ("main", "zone2"):
            z = state[group]
            if method == "getStatus":
                body = dict(z)
                if MODERN and group == "main":
                    body["actual_volume"] = {"mode": "db", "value": db(z["volume"]), "unit": "dB"}
                return self.ok(**body)
            if method == "setPower":
                z["power"] = "on" if q.get("power") == "on" else "standby"
                return self.ok()
            if method == "setVolume":
                v = q.get("volume", "")
                if v in ("up", "down"):
                    z["volume"] += 1 if v == "up" else -1
                else:
                    z["volume"] = int(v)
                return self.ok()
            if method == "setActualVolume" and MODERN:
                z["volume"] = int(round((float(q["value"]) + 80.5) / 0.5))
                return self.ok()
            if method == "setMute":
                z["mute"] = q.get("enable") == "true"
                return self.ok()
            if method == "setInput":
                z["input"] = q["input"]
                return self.ok()
            if method == "setSoundProgram":
                z["sound_program"] = q["program"]
                return self.ok()
            if method == "setPureDirect":
                z["pure_direct"] = q.get("enable") == "true"
                return self.ok()
            if method in ("controlCursor", "controlMenu") and MODERN:
                return self.ok()
        if group == "tuner":
            t = state["tuner"]
            if method == "getPlayInfo":
                return self.ok(band=t["band"], fm=t["fm"], am=t["am"])
            if method == "getPresetInfo":
                return self.ok(preset_info=presets, func_list=["clear"])
            if method == "setBand":
                t["band"] = q["band"]
                return self.ok()
            if method == "setFreq":
                b = t[q["band"]]
                b["freq"] += (100 if q["band"] == "fm" else 9) * (1 if q["tuning"] == "up" else -1)
                b["preset"] = 0
                return self.ok()
            if method == "recallPreset":
                p = presets[int(q["num"]) - 1]
                if p["number"] == 0:
                    return self.reply(200, json.dumps({"response_code": 4}))
                t["band"] = p["band"]
                t[p["band"]] = {"preset": int(q["num"]), "freq": p["number"]}
                state["main"]["input"] = "tuner"
                return self.ok()
        return self.reply(200, json.dumps({"response_code": 3}))

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode()
        print(self.client_address[0], "POST", self.path, body, flush=True)
        if self.path != "/YamahaRemoteControl/ctrl" or MODERN:
            return self.reply(404, "not found", "text/plain")
        if "Basic_Status" in body:
            val = int(db(state["main"]["volume"]) * 10)
            return self.reply(200, '<YAMAHA_AV rsp="GET" RC="0"><Main_Zone><Basic_Status>'
                              f'<Volume><Lvl><Val>{val}</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></Volume>'
                              '</Basic_Status></Main_Zone></YAMAHA_AV>', "text/xml")
        return self.reply(200, '<YAMAHA_AV rsp="PUT" RC="0"></YAMAHA_AV>', "text/xml")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "80"))
    print(f"mock Yamaha ({'modern' if MODERN else 'RX-V581'}) on :{port}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
