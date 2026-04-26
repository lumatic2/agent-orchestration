#!/usr/bin/env bash
# Wake yusun Windows PC (ASUS TUF X870E-PLUS, Realtek 2.5GbE)
# 매직 패킷 발사 후 ICMP transition으로 깨움 여부 검증.
#
# 다른 PC로 옮길 때: 환경변수로 override (스크립트 수정 불필요)
#   WAKE_MAC=AA:BB:CC:DD:EE:FF WAKE_BROADCAST=10.0.0.255 WAKE_TARGET_IP=10.0.0.50 wake-pc.sh
#
# Exit codes:
#   0 — 깨움 확인됨 또는 이미 깨어있던 상태
#   2 — 잘못된 설정값
#   3 — 매직 패킷은 보냈지만 ICMP transition 미관측 (wake 실패 / 방화벽 / S5)
set -euo pipefail

MAC="${WAKE_MAC:-A0:AD:9F:B6:56:A0}"
BROADCAST="${WAKE_BROADCAST:-192.168.200.255}"
TARGET_IP="${WAKE_TARGET_IP:-192.168.200.191}"

mac_re='^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$'
ipv4_re='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
[[ "$MAC"       =~ $mac_re  ]] || { echo "❌ invalid MAC: $MAC"            >&2; exit 2; }
[[ "$BROADCAST" =~ $ipv4_re ]] || { echo "❌ invalid BROADCAST: $BROADCAST" >&2; exit 2; }
[[ "$TARGET_IP" =~ $ipv4_re ]] || { echo "❌ invalid TARGET_IP: $TARGET_IP" >&2; exit 2; }

ping_once() { ping -c 1 -W 1000 -t 1 "$1" >/dev/null 2>&1; }

# Pre-check: 이미 깨어 있는지 (transition 측정 가능 여부 판단)
if ping_once "$TARGET_IP"; then
  WAS_AWAKE=1
  echo "ℹ️  $TARGET_IP already responsive — sending wake anyway, but transition won't be observable"
else
  WAS_AWAKE=0
fi

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

if [ "$WAS_AWAKE" -eq 1 ]; then
  echo "✅ already awake (no transition measured) — CRD 접속 가능"
  exit 0
fi

echo "⏳ waiting for $TARGET_IP to come online..."
for i in $(seq 1 24); do
  if ping_once "$TARGET_IP"; then
    echo "✅ $TARGET_IP newly online after ~$((i*5))s — wake confirmed"
    exit 0
  fi
  sleep 5
done
echo "⚠️  no ICMP after 120s — wake failed / firewall blocks ping / S5(완전종료) 상태"
exit 3
