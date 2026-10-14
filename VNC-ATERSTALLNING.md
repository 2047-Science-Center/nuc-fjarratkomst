# VNC-återställning — när skärmdelningen slutar funka efter reboot

Kom-ihåg-doc för när **macOS Cmd+K inte längre når en NUC:s skärm** (t.ex. efter en
omstart). Bygger på hur det faktiskt löstes. Läs även `README.md` och `setup-vnc.sh`
för grunduppsättningen.

> ⚠️ **Inga hemligheter i den här filen** — repo:t är publikt. Alla lösenord
> (NUC-inloggning, sudo, VNC) står i NUC-registret **`2047-NUC-register.xlsx`** (privat).
> Platshållare nedan: `<station>01` = användare/hostname, `<tailscale-ip>` = 100.x.y.z.

---

## Symptom → orsak → fix (snabbversion)

| | |
|---|---|
| **Symptom** | macOS Finder → Cmd+K → `vnc://<tailscale-ip>` ansluter inte ("det går inte att ansluta"). |
| **Orsak (vanligast)** | `x11vnc.service` är `enabled` men `inactive (dead)` — tjänsten startade inte (om)efter boot. Inget lyssnar på port 5900. |
| **Fix** | SSH in över Tailscale (överlever reboot) → `sudo systemctl restart x11vnc` → verifiera → anslut om. |

**Varför Tailscale/SSH funkar även när VNC inte gör det:** båda är headless
system-tjänster som startar vid boot utan grafisk session. VNC kräver däremot en
**inloggad grafisk session på `:0`** att spegla — finns ingen skärm, finns inget att dela.

---

## Återställnings-runbook (kopiera rad för rad)

> Skriv **inte** vinkelparenteserna `< >` bokstavligen. Shellen tolkar `<` som
> input-omdirigering → "no such file or directory". Byt ut platshållaren mot det riktiga
> värdet (t.ex. `pulsklockan01` / `100.x.y.z`).

### 1. Hitta NUC:ens Tailscale-IP (på Macen)
```bash
tailscale status
# Finns inte 'tailscale' i PATH? Kör med full sökväg:
/Applications/Tailscale.app/Contents/MacOS/Tailscale status
```
Leta efter raden för stationen, t.ex.:
```
100.x.y.z   <station>01   josef.sjonneby@   linux   idle
```
`idle` betyder **online/nåbar** (inte offline). Notera IP:t.

### 2. SSH in
```bash
ssh <station>01@<tailscale-ip>
# exempel från pulsklockan01:
# ssh pulsklockan01@100.x.y.z
```
**Gotchas:**
- **Användarnamnet är inte det bara datornamnet** — det är fulla namnet **med siffran**,
  samma som Tailscale-nodnamnet (t.ex. `pulsklockan01`, **inte** `pulsklockan`).
  Fel användare → "Permission denied" (SSH ger samma fel för fel användare som för fel
  lösenord, så dubbelkolla namnet först).
- **Namnkonvention:** Datornamn = Station med stor bokstav, användare = station med liten
  bokstav; en siffra läggs till per NUC vid dubbletter (`01`, `02` …).
- **Inloggning är normalt nyckelbaserad** (lösenordsfri, via SSH-nyckeln från
  `setup-remote.sh`). Frågar den ändå efter lösenord = den delade NUC-inloggningen
  (se registret).

### 3. Diagnos (på NUC:en via SSH)
```bash
who                                      # finns en grafisk :0-session?
systemctl status x11vnc --no-pager       # kör tjänsten?
sudo ss -ltnp | grep 5900                # lyssnar något på 5900?
```
Tolkning:
- `who` → rad med `tty7 ... (:0)` = grafisk session finns → autologin OK, problemet är
  bara VNC-tjänsten (**gren A** nedan). Ser du bara `pts/…` (din SSH-session) eller en
  inloggningsruta → ingen `:0` (**gren B**).
- `systemctl status x11vnc` → i vårt fall `enabled` men `Active: inactive (dead)` —
  tjänsten var helt enkelt inte igång.
- `ss ... 5900` → inget utskrivet = VNC nere (bekräftar).

### 4. Fix + verifiera
```bash
sudo systemctl restart x11vnc            # sudo-lösenord = NUC-inloggningen (se registret)
systemctl status x11vnc --no-pager       # ska visa: active (running)
sudo ss -ltnp | grep 5900                # ska visa: ...:5900 ... users:(("x11vnc"...))
```
Anslut sedan om från Macen:
```
Finder → Cmd+K → vnc://<tailscale-ip>
```
VNC-lösenord = se registret.

---

## Två grenar

**Gren A — `:0`-session finns (`who` visar `tty7 ... (:0)`)**
Autologin är OK. Starta bara om tjänsten (steg 4). Detta var vårt fall.

**Gren B — ingen `:0`-session**
Då är det autologin som är problemet, inte VNC. x11vnc har ingen skärm att spegla.
Åtgärd (Linux Mint, LightDM) — aktivera autologin via en drop-in:
```bash
sudo mkdir -p /etc/lightdm/lightdm.conf.d
sudo tee /etc/lightdm/lightdm.conf.d/50-autologin.conf >/dev/null <<EOF
[Seat:*]
autologin-user=<station>01
autologin-user-timeout=0
EOF
sudo reboot
```
Alternativt: be någon på plats logga in fysiskt så att en `:0`-session skapas, kör
sedan gren A. Efter reboot: kontrollera med `who` att `:0` finns och verifiera x11vnc.

---

## Öppet / att härda (EJ gjort än)

`x11vnc.service` är `enabled` men dog efter boot. Trolig orsak: tjänsten startade
**innan `:0`-sessionen / Xauthority var redo**, och `Restart=on-failure` gav upp efter
sina försök. Att utreda och göra boot-robust:

```bash
journalctl -u x11vnc -b --no-pager | tail -30   # vad sa den vid senaste boot?
```
Möjliga åtgärder (välj efter vad loggen visar):
- Starkare beroende på den grafiska sessionen i unit-filen (hårdare `After=`/`Wants=`
  mot `graphical.target` / display manager-target), så tjänsten startar efter `:0`.
- Oändlig omstart i stället för att ge upp: `Restart=always` + rimlig `RestartSec`
  (x11vnc körs redan med `-forever -loop` för att vänta in/återansluta till `:0`).
- Ev. en kort väntan/retry på Xauthority innan `ExecStart`.

Markerat som **inte klart** — tills detta är fixat kan en manuell
`sudo systemctl restart x11vnc` behövas efter varje omstart (se runbooken ovan).
