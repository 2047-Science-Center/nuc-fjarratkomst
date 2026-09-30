# NUC — fjärråtkomst

Station-oberoende kit för att fjärrstyra en Linux-NUC (Mint/Ubuntu) från din dator,
var NUC:en än står — utan att öppna portar i lokalens router. Funkar för vilken
2047-station som helst (FLYKTEN, Förhandlingen m.fl.).

Tre lager:

| Lager | Verktyg | Vad du gör |
|---|---|---|
| Nätverk (nå NUC:en alls) | **Tailscale** | Privat mesh-VPN — NUC:en dyker upp med namn/IP hos dig |
| Terminal (nästan allt) | **SSH** | Uppdatera appen, `systemctl`, redigera config, touch-mappning |
| Skärm (se & klicka) | **RustDesk** | Se stationen, köra pavucontrol/EasyEffects, klicka i GUI |

## 1. På NUC:en (en gång)
```bash
git clone https://github.com/2047-Science-Center/nuc-fjarratkomst.git ~/nuc-fjarratkomst
cd ~/nuc-fjarratkomst
bash setup-remote.sh
```
Under körningen skrivs en **Tailscale-inloggningslänk** ut — öppna den och logga in med
ditt Tailscale-konto (skapa gratis på tailscale.com). Namnge enheten, t.ex. `flykten-1`.

När det är klart visas (och sparas i `~/nuc-fjarratkomst.txt`):
- **Tailscale-IP** + SSH-kommando
- **RustDesk-ID** + **lösenord**

## 2. På din dator (en gång)
- **Tailscale:** installera från Mac App Store eller tailscale.com, logga in med **samma konto** som NUC:arna använder.
- **RustDesk:** ladda ned Mac-appen från rustdesk.com (om du vill se skärmen).
- **SSH:** finns redan i Terminal (macOS/Linux) / `ssh` på Windows.
- **SSH-nyckel** (för lösenordsfri inloggning) — har du ingen, skapa en:
  ```bash
  ls ~/.ssh/id_ed25519.pub 2>/dev/null || ssh-keygen -t ed25519
  cat ~/.ssh/id_ed25519.pub        # hela raden → klistras in i remote.env (SSH_PUBKEY)
  ```

## Klick-fri utrullning (flera stationer)
Vill du slippa inloggningslänk och lösenord på varje NUC — fyll i `remote.env` **en gång**
och återanvänd den på alla:
1. Skapa en **återanvändbar Tailscale auth-nyckel**: login.tailscale.com/admin/settings/keys → *Reusable*.
2. Kopiera mallen och fyll i auth-nyckel + din SSH-publika nyckel:
   ```bash
   cd ~/nuc-fjarratkomst
   cp remote.env.example remote.env
   nano remote.env        # TS_AUTHKEY, SSH_PUBKEY, ev. TS_HOSTNAME
   bash setup-remote.sh
   ```
Då ansluter NUC:en till Tailscale automatiskt och du kan SSH:a in utan lösenord direkt.
`remote.env` är gitignore:ad — hemligheterna stannar lokalt. Sätt `TS_HOSTNAME` per NUC
(`flykten-1`, `forhandling-1` …) så får de rätt namn direkt.

## 3. Ansluta
**Terminal:**
```bash
ssh DITTNAMN@100.x.y.z          # Tailscale-IP:t från steg 1
```
eller med Tailscale-namnet:
```bash
ssh DITTNAMN@flykten-1
```
Grafiska kommandon funkar också över SSH, t.ex. touch-mappning:
```bash
DISPLAY=:0 xinput map-to-output "NAMN" HDMI-1
```

**Skärm:** öppna RustDesk på din dator, skriv in NUC:ens **ID**, tryck Anslut, ange
**lösenordet**. Obevakad åtkomst är på, så ingen behöver klicka "godkänn" på plats.

## Bra att veta
- NUC:en måste vara **på och uppkopplad**. Avstängd eller nät nere = ingen åtkomst.
- **Flera stationer:** kör kittet på varje NUC och döp dem i Tailscale (`flykten-1`,
  `forhandling-1` …). Alla dyker upp i samma lista på din dator.
- **Säkerhet:** öppna aldrig portar i routern — Tailscale sköter allt krypterat.
  RustDesk-lösenordet är starkt och slumpat; byt det i RustDesk-appen vid behov.
- **Knutet till installationen, inte datornamnet:** Tailscale-identiteten och
  RustDesk-ID:t sitter i mjukvarans config på maskinen. Byt hostname fritt; installerar
  du om OS:et blir det en ny Tailscale-nod och nytt RustDesk-ID (para om då).
- **Klona inte** en NUC-disk till en annan NUC — då dupliceras Tailscale-nyckeln och
  RustDesk-ID:t och krockar. Kör `setup-remote.sh` färskt på varje maskin.

## Felsökning
- **Når inte NUC:en:** kolla att den är online i Tailscale-panelen (login.tailscale.com);
  kör `tailscale status` på NUC:en.
- **RustDesk-ID saknas:** öppna RustDesk-appen på NUC:en en gång, slå på
  *Inställningar → Aktivera obevakad åtkomst*, så visas ID:t.
- **SSH nekar:** första gången svarar du `yes` på nyckel-frågan. Vill du slippa lösenord,
  sätt upp en SSH-nyckel (`ssh-copy-id DITTNAMN@<ip>`).
