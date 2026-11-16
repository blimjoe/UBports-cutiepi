#!/usr/bin/env python3
"""Collect a WPA2/WPA3-transition personal Wi-Fi profile locally, without logging it."""
import getpass
import os
from pathlib import Path
import re
import uuid


def keyfile_value(value):
    return (value.replace("\\", "\\\\").replace("\n", "\\n")
            .replace("\r", "\\r").replace("\t", "\\t")
            .replace(" ", "\\s"))


def main():
    if not os.isatty(0):
        raise SystemExit("请在交互式终端运行此脚本；不要把密码作为命令行参数。")
    ssid = input("Wi-Fi 名称（SSID）：")
    if not 1 <= len(ssid.encode("utf-8")) <= 32:
        raise SystemExit("SSID 必须为 1 到 32 字节。")
    psk = getpass.getpass("Wi-Fi 密码（输入不显示）：")
    if not (8 <= len(psk.encode("utf-8")) <= 63 or re.fullmatch(r"[0-9a-fA-F]{64}", psk)):
        raise SystemExit("此脚本支持个人 Wi-Fi：密码为 8 到 63 字节，或 64 位十六进制 PSK。")
    security = input("安全类型：回车选择 WPA2/混合模式；纯 WPA3 输入 sae：").strip() or "wpa-psk"
    if security not in ("wpa-psk", "sae"):
        raise SystemExit("安全类型只能为 wpa-psk 或 sae。")
    profile = (
        f"[connection]\nid=cutiepi-bootstrap\nuuid={uuid.uuid4()}\ntype=wifi\nautoconnect=true\n"
        f"\n[wifi]\nmode=infrastructure\nssid={keyfile_value(ssid)}\n"
        f"\n[wifi-security]\nkey-mgmt={security}\npsk={keyfile_value(psk)}\n"
        "\n[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n"
    )
    dest = Path(__file__).resolve().parent.parent / "artifacts" / "wifi.nmconnection"
    dest.parent.mkdir(exist_ok=True)
    fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as output:
            output.write(profile)
    except BaseException:
        dest.unlink(missing_ok=True)
        raise
    print("Wi-Fi 配置已保存。请回到聊天回复“已配置”，不要发送密码。")


if __name__ == "__main__":
    main()
