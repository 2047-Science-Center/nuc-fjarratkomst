#!/usr/bin/env bash
# =============================================================================
# NUC — fjärråtkomst (station-oberoende). Installerar på en Linux Mint/Ubuntu-NUC:
#   1) openssh-server      → terminal-styrning (SSH) från din dator
#   2) Tailscale           → privat mesh-VPN så NUC:en nås var den än står,
#                            utan portöppningar i lokalens router
#   3) RustDesk            → se & klicka på skärmen (obevakad åtkomst)
#
# Fungerar för vilken stations-NUC som helst (FLYKTEN, Förhandlingen, m.fl.).
#
# Kör på NUC:en, som din vanliga användare (inte sudo):
#     bash setup-remote.sh
#
# På din dator: installera Tailscale + RustDesk och logga in — se README.md.
# =============================================================================
set -euo pipefail

say() { printf '\n\033[1;33m== %s\033[0m\n' "$*"; }

if [ "$(id -un)" = "root" ]; then
  echo "Kör INTE som root/sudo — kör som din vanliga användare." >&2
  exit 1
fi

# --- 1) SSH (terminal-styrning) --------------------------------------------
say "Installerar openssh-server (SSH)"
sudo apt update
sudo apt install -y openssh-server curl
sudo systemctl enable --now ssh 2>/dev/null || sudo systemctl enable --now sshd 2>/dev/null || true

# --- 2) Tailscale (privat mesh-VPN) ----------------------------------------
if ! command -v tailscale >/dev/null 2>&1; then
  say "Installerar Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi
say "Kopplar upp Tailscale — LOGGA IN via länken som skrivs ut nedan"
echo "(Använd samma Tailscale-konto som på din dator. Namnge gärna enheten, t.ex. flykten-1.)"
sudo tailscale up
TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"

# --- 3) RustDesk (grafiskt fjärrskrivbord, obevakad åtkomst) ---------------
if ! command -v rustdesk >/dev/null 2>&1; then
  say "Hämtar senaste RustDesk (.deb)"
  URL="$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
    | grep -o 'https://[^"]*x86_64\.deb' | head -1)"
  if [ -z "$URL" ]; then
    echo "Kunde inte hitta RustDesk-nedladdningen automatiskt." >&2
    echo "Ladda ned .deb manuellt från https://github.com/rustdesk/rustdesk/releases och kör:" >&2
    echo "  sudo apt install -y ./rustdesk-*.deb" >&2
  else
    TMP="$(mktemp --suffix=.deb)"
    curl -fsSL "$URL" -o "$TMP"
    sudo apt install -y "$TMP" || sudo dpkg -i "$TMP" || true
    sudo apt-get -y -f install || true
    rm -f "$TMP"
  fi
fi

# Starta RustDesk-tjänsten (obevakad åtkomst = du slipper klicka "godkänn" på plats).
sudo systemctl enable --now rustdesk 2>/dev/null || true
sleep 3

# Sätt ett permanent lösenord (genereras här; skrivs ut EN gång, sparas ej i git).
say "Sätter permanent RustDesk-lösenord för obevakad åtkomst"
PW="$(openssl rand -base64 12 2>/dev/null | tr -dc 'A-Za-z0-9' | cut -c1-12)"
[ -n "$PW" ] || PW="$(head -c 9 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-12)"
sudo rustdesk --password "$PW" 2>/dev/null || rustdesk --password "$PW" 2>/dev/null || true
RD_ID="$(sudo rustdesk --get-id 2>/dev/null || rustdesk --get-id 2>/dev/null || true)"

# Spara åtkomst-uppgifterna lokalt (bara på NUC:en, läsbar endast av dig).
CRED="$HOME/nuc-fjarratkomst.txt"
{
  echo "NUC — fjärråtkomst (skapad $(date '+%Y-%m-%d %H:%M'))"
  echo "Värdnamn:            $(hostname)"
  echo "Tailscale-IP:        ${TS_IP:-(kör: tailscale ip -4)}"
  echo "SSH:                 ssh $(id -un)@${TS_IP:-<tailscale-namn>}"
  echo "RustDesk-ID:         ${RD_ID:-(öppna RustDesk-appen för att se ID)}"
  echo "RustDesk-lösenord:   ${PW}"
} > "$CRED"
chmod 600 "$CRED"

say "KLART — fjärråtkomst installerad"
cat <<EOF

  Terminal (SSH):     ssh $(id -un)@${TS_IP:-<tailscale-IP>}
  Skärm (RustDesk):   ID ${RD_ID:-<öppna RustDesk-appen>}   lösenord ${PW}

  Uppgifterna är sparade i:  $CRED   (endast läsbar av dig)

Nästa steg på din dator (se README.md):
  1) Installera Tailscale, logga in med SAMMA konto.
  2) Terminal:  ssh $(id -un)@${TS_IP:-<tailscale-IP>}
  3) Skärm:     installera RustDesk, ange ID + lösenord ovan.

Tips: syns inget RustDesk-ID ovan — öppna RustDesk-appen på NUC:en en gång,
slå på "Aktivera obevakad åtkomst" i inställningarna, så visas ID:t där.
EOF
