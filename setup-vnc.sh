#!/usr/bin/env bash
# =============================================================================
# NUC — skärmdelning via VNC över Tailscale (station-oberoende).
# Installerar x11vnc + en systemd-tjänst som speglar den FYSISKA skärmen (:0)
# och startar av sig själv vid varje boot. Anslut från macOS utan extra app:
#     Finder → Cmd+K → vnc://<tailscale-ip>
#
# Varför VNC och inte RustDesk: går rakt genom Tailscale, ingen tredjeparts-
# server som kan vara "ej redo", och macOS har klienten inbyggd.
#
# KRÄVER:
#   • Tailscale igång (kör setup-remote.sh först).
#   • En INLOGGAD grafisk session på :0 (autologin-kiosk) — annars finns ingen
#     skärm att spegla.
#
# Konfig via remote.env eller miljövariabel:
#   VNC_PW   VNC-lösenord (max 8 ASCII-tecken, inga å/ä/ö — VNC-protokollets gräns).
#            Sätts ej → skriptet frågar interaktivt.
#
# Kör på NUC:en, som din vanliga användare (inte sudo):
#     bash setup-vnc.sh
# =============================================================================
set -euo pipefail

say() { printf '\n\033[1;33m== %s\033[0m\n' "$*"; }

if [ "$(id -un)" = "root" ]; then
  echo "Kör INTE som root/sudo — kör som din vanliga användare." >&2
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/remote.env" ] && . "$HERE/remote.env"
VNC_PW="${VNC_PW:-}"

# --- 1) Installera x11vnc ---------------------------------------------------
say "Installerar x11vnc"
sudo apt update
sudo apt install -y x11vnc

# --- 2) Lösenord (max 8 ASCII-tecken) ---------------------------------------
if [ -z "$VNC_PW" ]; then
  read -rp "Välj VNC-lösenord (max 8 ASCII-tecken, inga å/ä/ö): " VNC_PW
fi
mkdir -p "$HOME/.vnc"
x11vnc -storepasswd "$VNC_PW" "$HOME/.vnc/passwd" >/dev/null
chmod 600 "$HOME/.vnc/passwd"
PASSFILE="$HOME/.vnc/passwd"

# --- 3) systemd-tjänst ------------------------------------------------------
# -allow 100.  → bara Tailscale-adresser (100.x) får ansluta. OBS: x11vnc:s
#               -allow matchar som TEXT-PREFIX, inte CIDR — därför "100." och
#               ALDRIG "100.64.0.0/10" (det matchar ingen och blockerar alla).
# -auth guess  → hittar den aktiva :0-sessionens Xauthority.
# -forever -loop → fortsätt serva, och vänta in/återanslut till :0.
say "Skapar systemd-tjänst x11vnc"
sudo tee /etc/systemd/system/x11vnc.service >/dev/null <<EOF
[Unit]
Description=x11vnc skärmdelning av :0 (över Tailscale)
After=graphical.target
Wants=graphical.target

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -display :0 -auth guess -rfbauth $PASSFILE -forever -loop -shared -noxdamage -allow 100. -rfbport 5900
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now x11vnc
sleep 2

# --- 4) Verifiera + skriv ut anslutning -------------------------------------
TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"
say "KLART — VNC installerad"
if sudo ss -ltnp 2>/dev/null | grep -q ':5900'; then
  echo "x11vnc lyssnar på 5900 ✓"
else
  echo "VARNING: port 5900 lyssnar inte än — kolla:  systemctl status x11vnc" >&2
fi
cat <<EOF

Anslut från macOS:  Finder → Cmd+K → vnc://${TS_IP:-<tailscale-ip>}
Lösenord:           det du valde (VNC_PW)

Krav att komma ihåg:
  • NUC:en måste ha en INLOGGAD grafisk session på :0 (autologin).
  • Tailscale måste vara igång (setup-remote.sh).
Startar om tjänsten:  sudo systemctl restart x11vnc
EOF
