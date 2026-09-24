#!/usr/bin/env python3
"""Denon の AV レシーバー（/goform の HTTP API）のふりをする開発用のサーバー。

Yamaha 対応などで共通部分を変えたときに、Denon 側の動きが変わっていないかを実機なしで確かめるためのもの。
Telnet（ポート 23）は用意しないので、アプリは HTTP でコマンドを送る（実機で Telnet がつながらないときと同じ経路）。

使い方:
  python3 scripts/mock-denon.py        # 0.0.0.0:8080
アプリ側: -debugConnectHost localhost -autoConnect NO（127.0.0.1 は Yamaha の模擬で使うので別の名前にする）
"""
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

state = {"power": "ON", "vol": -35.0, "mute": "off", "input": "BD", "z2power": "OFF", "z2vol": -40.0}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *args):
        pass

    def reply(self, status, body):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/xml")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path
        if not ("StatusLite" in path):
            print("GET", unquote(path), flush=True)
        if path.startswith("/goform/Deviceinfo.xml"):
            return self.reply(200, "<Device_Info><ModelName>AVR-X3800H</ModelName><BrandCode>0</BrandCode>"
                              "<CategoryName>AV RECEIVER</CategoryName><DeviceZones>2</DeviceZones>"
                              "<MacAddress>0005CD000000</MacAddress></Device_Info>")
        if path.startswith("/goform/formMainZone_MainZoneXmlStatusLite.xml"):
            return self.reply(200, f"<item><Power><value>{state['power']}</value></Power>"
                              f"<InputFuncSelect><value>{state['input']}</value></InputFuncSelect>"
                              f"<MasterVolume><value>{state['vol']}</value></MasterVolume>"
                              f"<Mute><value>{state['mute']}</value></Mute></item>")
        if path.startswith("/goform/formZone2_Zone2XmlStatusLite.xml"):
            return self.reply(200, f"<item><Power><value>{state['z2power']}</value></Power>"
                              f"<InputFuncSelect><value>TUNER</value></InputFuncSelect>"
                              f"<MasterVolume><value>{state['z2vol']}</value></MasterVolume>"
                              f"<Mute><value>off</value></Mute></item>")
        if path.startswith("/goform/formiPhoneAppDirect.xml?"):
            cmd = unquote(path.split("?", 1)[1])
            if cmd == "PWON": state["power"] = "ON"
            elif cmd == "PWSTANDBY": state["power"] = "STANDBY"
            elif cmd == "MVUP": state["vol"] += 0.5
            elif cmd == "MVDOWN": state["vol"] -= 0.5
            elif cmd.startswith("MV"):
                digits = cmd[2:]
                state["vol"] = (int(digits) / 10 if len(digits) == 3 else int(digits)) - 80
            elif cmd == "MUON": state["mute"] = "on"
            elif cmd == "MUOFF": state["mute"] = "off"
            elif cmd.startswith("SI"): state["input"] = cmd[2:]
            elif cmd == "Z2ON": state["z2power"] = "ON"
            elif cmd == "Z2UP": state["z2vol"] += 0.5
            return self.reply(200, "")
        return self.reply(404, "")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    print(f"mock Denon AVR-X3800H on :{port}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
