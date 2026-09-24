#!/usr/bin/env python3
"""Denon の AV レシーバー（/goform の HTTP API）のふりをする開発用のサーバー。

Yamaha 対応などで共通部分を変えたときに、Denon 側の動きが変わっていないかを実機なしで確かめるためのもの。
Telnet も TELNET_PORT（既定 23）で待ち受け、状態が変わると接続中のクライアントに通知（例: "MSSTEREO"）を送る。
本体の物理リモコンでの操作は GET /debug/remote?MSSTEREO のように真似できる（HTTP のコマンドと同じ書式）。

使い方:
  PORT=18080 python3 scripts/mock-denon.py   # HTTP 0.0.0.0:18080（シミュレータからは 8080 だと届かなかった）、Telnet :23
アプリ側: -debugConnectHost 127.0.0.1:18080 -autoConnect NO（ポートを付けると Denon として接続する）
"""
import os
import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

telnet_clients = []


def notify(line):
    for c in list(telnet_clients):
        try:
            c.sendall((line + "\r").encode())
        except OSError:
            telnet_clients.remove(c)


def apply_command(cmd):
    """HTTP・Telnet・物理リモコンの真似のどれから来ても同じように状態を変え、Telnet に通知する"""
    if cmd == "PWON": state["power"] = "ON"
    elif cmd == "PWSTANDBY": state["power"] = "STANDBY"
    elif cmd == "MVUP": state["vol"] += 0.5
    elif cmd == "MVDOWN": state["vol"] -= 0.5
    elif cmd.startswith("MV") and cmd[2:].isdigit():
        digits = cmd[2:]
        state["vol"] = (int(digits) / 10 if len(digits) == 3 else int(digits)) - 80
    elif cmd == "MUON": state["mute"] = "on"
    elif cmd == "MUOFF": state["mute"] = "off"
    elif cmd.startswith("SI"): state["input"] = cmd[2:]
    elif cmd.startswith("MS") and not cmd.endswith("?"):
        state["ms"] = cmd[2:]
        notify("MS" + state["ms"])
        return
    elif cmd == "Z2ON": state["z2power"] = "ON"
    elif cmd == "Z2UP": state["z2vol"] += 0.5
    else:
        return
    notify(cmd)


def telnet_server(port):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", port))
    srv.listen()
    print(f"telnet on :{port}", flush=True)
    while True:
        conn, addr = srv.accept()
        print("TELNET connected", addr[0], flush=True)
        telnet_clients.append(conn)
        threading.Thread(target=telnet_reader, args=(conn,), daemon=True).start()


def telnet_reader(conn):
    buf = b""
    while True:
        data = conn.recv(1024)
        if not data:
            print("TELNET closed", flush=True)
            if conn in telnet_clients: telnet_clients.remove(conn)
            return
        buf += data
        while b"\r" in buf:
            line, buf = buf.split(b"\r", 1)
            cmd = line.decode(errors="ignore").strip()
            print("TELNET <", cmd, flush=True)
            apply_command(cmd)


state = {"ms": "STEREO", "power": "ON", "vol": -35.0, "mute": "off", "input": "BD", "z2power": "OFF", "z2vol": -40.0}


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
        if path.startswith("/goform/formiPhoneAppDirect.xml?") or path.startswith("/debug/remote?"):
            apply_command(unquote(path.split("?", 1)[1]))
            return self.reply(200, "")
        return self.reply(404, "")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    print(f"mock Denon AVR-X3800H on :{port}", flush=True)
    threading.Thread(target=telnet_server, args=(int(os.environ.get("TELNET_PORT", "23")),), daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
