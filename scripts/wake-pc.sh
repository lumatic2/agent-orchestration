#!/usr/bin/env bash
# Wake yusun Windows PC (ASUS TUF X870E-PLUS, Realtek 2.5GbE)
# 매직 패킷을 LAN 브로드캐스트로 발사 후, ping으로 깨어남 검증.
# M4 → ~/bin/wake-pc.sh 위치에 설치, Telegram /wake-pc 슬래시 명령에서 호출.
set -euo pipefail
MAC="A0:AD:9F:B6:56:A0"
BROADCAST="192.168.200.255"
TARGET_IP="192.168.200.191"

python3 - "$MAC" "$BROADCAST" <<PY
import socket, sys
mac, bcast = sys.argv[1], sys.argv[2]
hw = bytes.fromhex(mac.replace(":","").replace("-",""))
pkt = b"\xff" * 6 + hw * 16
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
for port in (9, 7):
    s.sendto(pkt, (bcast, port))
print(f"📨 magic packet sent to {mac} via {bcast}:9,7 ({len(pkt)}B)")
PY

echo "⏳ waiting for $TARGET_IP to come online..."
for i in $(seq 1 24); do
  if ping -c 1 -W 1000 -t 1 "$TARGET_IP" >/dev/null 2>&1; then
    echo "✅ $TARGET_IP alive after ~$((i*5))s"
    exit 0
  fi
  sleep 5
done
echo "⚠️ no ICMP after 120s — already awake / firewall blocks ping / not woken"
