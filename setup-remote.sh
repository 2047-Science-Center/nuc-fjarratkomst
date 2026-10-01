#!/usr/bin/env bash
# =============================================================================
# NUC — fjärråtkomst (station-oberoende). Installerar på en Linux Mint/Ubuntu-NUC:
#   1) openssh-server      → terminal-styrning (SSH) från din dator
#   2) Tailscale           → privat mesh-VPN så NUC:en nås var den än står,
#                            utan portöppningar i lokalens router
#   3) RustDesk            → se & klicka på skärmen (obevakad åtkomst)
#
# KLICK-FRI UTRULLNING (valfritt): fyll i remote.env (kopiera remote.env.example)
# med en Tailscale auth-nyckel + din SSH-publika nyckel, så ansluter NUC:en helt
# automatiskt utan inloggningslänk och du kan SSH:a utan lösenord. remote.env är
# gitignore:ad → hemligheterna hamnar aldrig i repot.
#
# Kör på NUC:en, som din vanliga användare (inte sudo):
#     bash setup-remote.sh
# =============================================================================
set -euo pipefail

say() { printf '\n\033[1;33m== %s\033[0m\n' "$*"; }

if [ "$(id -un)" = "root" ]; then
  echo "Kör INTE som root/sudo — kör som din vanliga användare." >&2
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Ladda valfri lokal konfig (gitignore:ad) för klick-fri utrullning.
[ -f "$HERE/remote.env" ] && . "$HERE/remote.env"

TS_AUTHKEY="${TS_AUTHKEY:-}"      # Tailscale auth-nyckel (tskey-…) → klick-fri anslutning
TS_HOSTNAME="${TS_HOSTNAME:-}"    # enhetsnamn i Tailscale, t.ex. flykten-1
SSH_PUBKEY="${SSH_PUBKEY:-}"      # din publika SSH-nyckel (ssh-ed25519 AAAA…) → lösenordsfri SSH
RUSTDESK_PW="${RUSTDESK_PW:-}"    # valfritt fast RustDesk-lösen (annars slumpas)

# --- 1) SSH (terminal-styrning) --------------------------------------------
say "Installerar openssh-server (SSH)"
sudo apt update
sudo apt install -y openssh-server curl
sudo systemctl enable --now ssh 2>/dev/null || sudo systemctl enable --now sshd 2>/dev/null || true

# SSH-nyckel: lägg in din publika nyckel så du slipper lösenord.
if [ -n "$SSH_PUBKEY" ]; then
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
  if ! grep -qF "$SSH_PUBKEY" "$HOME/.ssh/authorized_keys"; then
    echo "$SSH_PUBKEY" >> "$HOME/.ssh/authorized_keys"
    echo "SSH-nyckel tillagd i authorized_keys (lösenordsfri inloggning)."
  else
    echo "SSH-nyckeln fanns redan i authorized_keys."
  fi
fi

# --- 2) Tailscale (privat mesh-VPN) ----------------------------------------
if ! command -v tailscale >/dev/null 2>&1; then
  say "Installerar Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi
UP_ARGS=()
[ -n "$TS_HOSTNAME" ] && UP_ARGS+=("--hostname=$TS_HOSTNAME")
if [ -n "$TS_AUTHKEY" ]; then
  say "Ansluter Tailscale med auth-nyckel (klick-fritt)"
  sudo tailscale up --authkey="$TS_AUTHKEY" "${UP_ARGS[@]}"
else
  say "Kopplar upp Tailscale — LOGGA IN via länken nedan (ingen auth-nyckel angiven)"
  echo "(Använd samma Tailscale-konto som på din dator. Tips: sätt TS_AUTHKEY i remote.env för klick-fri utrullning.)"
  sudo tailscale up "${UP_ARGS[@]}"
fi
TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"

# --- 3) RustDesk (grafiskt fjärrskrivbord, obevakad åtkomst) ---------------
if ! command -v rustdesk >/dev/null 2>&1; then
  say "Hämtar senaste RustDesk (.deb)"
  URL="$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
    | grep -o 'https://[^"]*x86_64\.deb' | head -1)"
  if [ -z "$URL" ]; then
    echo "Kunde inte hitta RustDesk-nedladdningen automatiskt." >&2
    echo "Ladda ned .deb från https://github.com/rustdesk/rustdesk/releases och kör:" >&2
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

# Permanent lösenord: använd RUSTDESK_PW om satt, annars slumpa.
say "Sätter permanent RustDesk-lösenord för obevakad åtkomst"
PW="$RUSTDESK_PW"
if [ -z "$PW" ]; then
  PW="$(openssl rand -base64 12 2>/dev/null | tr -dc 'A-Za-z0-9' | cut -c1-12)"
  [ -n "$PW" ] || PW="$(head -c 9 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-12)"
fi
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

$([ -n "$SSH_PUBKEY" ] && echo "SSH-nyckel installerad → logga in utan lösenord." || echo "Tips: sätt SSH_PUBKEY i remote.env för lösenordsfri SSH.")
$([ -n "$TS_AUTHKEY" ] && echo "Tailscale anslöts klick-fritt via auth-nyckel." || echo "Tips: sätt TS_AUTHKEY i remote.env för klick-fri anslutning på nästa NUC.")

Nästa NUC går helt automatiskt om remote.env är ifylld — se README.md.
EOF
