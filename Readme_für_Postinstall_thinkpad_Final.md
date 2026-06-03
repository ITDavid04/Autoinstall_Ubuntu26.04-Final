# D3023 – Software-Setup & Systemkonfiguration

> **Zielgruppe:** Umschüler Fachinformatiker Anwendungsentwicklung / Systemintegration  
> **Datei:** `install-software.sh`  
> **System:** Ubuntu (Laborrechner D3023, Benutzer `max`)

---

## Inhaltsverzeichnis

1. [Überblick](#überblick)
2. [Netzwerkerkennung](#1-netzwerkerkennung)
3. [System-Anpassungen](#2-system-anpassungen)
4. [Kernel-Optimierung](#3-kernel-optimierung)
5. [Debloat – Systembereinigung](#4-debloat--systembereinigung)
6. [Online-Installation](#5-online-installation)
   - [Firewall (UFW)](#51-firewall-ufw)
   - [SSH-Server](#52-ssh-server)
   - [Browser & Desktop](#53-browser--desktop)
   - [Entwicklungstools](#54-entwicklungstools)
   - [Docker](#55-docker)
   - [Flatpak-Apps](#56-flatpak-apps)
   - [Pausen-Erinnerung](#57-pausen-erinnerung)
7. [TPM 2.0 Auto-Unlock (LUKS)](#6-tpm-20-auto-unlock-luks)
8. [Installierte Software – Übersicht](#7-installierte-software--übersicht)
9. [Nach dem ersten Boot – Checkliste](#8-nach-dem-ersten-boot--checkliste)
10. [Wichtige Befehle zum Nachschlagen](#9-wichtige-befehle-zum-nachschlagen)

---

## Überblick

Das Script `install-software.sh` richtet einen frisch installierten Ubuntu-Rechner vollautomatisch ein. Es läuft nach der Erstinstallation und erledigt:

- Systemhärtung (Sudo, Auto-Updates, Kernel-Parameter)
- Entfernung unnötiger Vorinstallationen ("Debloat")
- Installation aller Arbeitstools (Docker, VS Code, Browser usw.)
- Absicherung per Firewall und SSH
- Automatisches LUKS-Entsperren via TPM 2.0

Das Script erkennt selbst, ob eine Internetverbindung besteht, und arbeitet im Offline-Modus nur die lokalen Schritte ab.

---

## 1. Netzwerkerkennung

```bash
if ping -c 1 -W 3 google.com &> /dev/null; then
    ONLINE=true
fi
```

**Was passiert hier?**  
Mit `ping` wird genau ein Paket an `google.com` geschickt (Timeout: 3 Sekunden). Kommt eine Antwort, gilt das System als online. Die Variable `ONLINE` steuert dann, ob der Installationsblock mit apt, Docker usw. überhaupt ausgeführt wird.

> **Lernpunkt:** `&> /dev/null` leitet sowohl stdout als auch stderr in den Papierkorb um – die Ausgabe des `ping`-Befehls interessiert uns nicht, nur sein Exit-Code (0 = Erfolg).

---

## 2. System-Anpassungen

### Auto-Updates deaktivieren

Im Laborbetrieb sollen Rechner nicht unkontrolliert Updates installieren. Das Script deaktiviert dafür mehrere Ubuntu-Mechanismen:

| Maßnahme | Befehl / Datei |
|---|---|
| Timer-Units stoppen | `systemctl disable apt-daily.timer apt-daily-upgrade.timer` |
| Services maskieren | `systemctl mask apt-daily.service` |
| Paket entfernen | `apt-get purge unattended-upgrades` |
| APT-Konfiguration | `/etc/apt/apt.conf.d/20auto-upgrades` |

Die Datei `/etc/apt/apt.conf.d/20auto-upgrades` wird auf alle Nullen gesetzt:

```
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::Unattended-Upgrade "0";
```

### Sudo ohne Passwort

```bash
echo "%sudo ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/01-admin-nopasswd
```

Alle Mitglieder der Gruppe `sudo` dürfen jeden Befehl ohne Passwort ausführen. Die Datei bekommt Rechte `0440` – das ist die von `visudo` geforderte Mindestberechtigung für sudoers-Dateien.

> **Sicherheitshinweis:** `NOPASSWD: ALL` ist praktisch im Labor, aber in Produktivumgebungen eine schlechte Idee. In der Prüfungsvorbereitung: Begründung kennen!

---

## 3. Kernel-Optimierung

```bash
cat <<EOF | sudo tee /etc/sysctl.d/99-performance.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=15
EOF
sudo sysctl -p /etc/sysctl.d/99-performance.conf
```

| Parameter | Wert | Bedeutung |
|---|---|---|
| `vm.swappiness` | `10` | Kernel nutzt Swap erst, wenn RAM zu 90 % voll ist (Standard: 60) |
| `vm.vfs_cache_pressure` | `50` | Verzeichnis-Cache wird länger im RAM gehalten |
| `vm.dirty_ratio` | `15` | Bis zu 15 % des RAM dürfen ungeschriebene Daten ("dirty pages") halten |

`sysctl -p` lädt die Datei sofort, ohne Neustart.

---

## 4. Debloat – Systembereinigung

Ubuntu Desktop kommt mit vielen vorinstallierten Paketen, die im Laborbetrieb nicht benötigt werden.

### Snap komplett entfernen

```bash
# Alle Snaps deinstallieren
for SNAP_PKG in $(snap list | awk 'NR>1 {print $1}'); do
    sudo snap remove --purge "$SNAP_PKG"
done

# snapd deaktivieren und maskieren
sudo systemctl mask snapd.service snapd.socket
sudo apt-get purge snapd

# Snap für immer sperren
printf 'Package: snapd\nPin: release a=*\nPin-Priority: -1\n' \
    | sudo tee /etc/apt/preferences.d/block-snapd
```

`Pin-Priority: -1` in `/etc/apt/preferences.d/` bedeutet: APT soll dieses Paket **niemals** installieren, auch nicht als Abhängigkeit.

### Weitere entfernte Pakete

| Kategorie | Pakete |
|---|---|
| Office | `libreoffice*`, `libobasis*` |
| Spiele | `aisleriot`, `gnome-mahjongg`, `gnome-mines`, `gnome-sudoku` |
| Multimedia | `cheese`, `rhythmbox`, `shotwell`, `totem` |
| Browser (vorinstalliert) | `firefox`, `thunderbird` |

---

## 5. Online-Installation

Alle folgenden Schritte laufen nur, wenn `ONLINE=true` erkannt wurde.

### 5.1 Firewall (UFW)

**UFW** (Uncomplicated Firewall) ist das Frontend für `iptables` unter Ubuntu.

```bash
sudo ufw allow 8080/tcp   # Webentwicklung / lokale Server
sudo ufw allow 2222/tcp   # SSH (nicht Standardport 22!)
sudo ufw default deny incoming
sudo ufw --force enable
```

| Port | Protokoll | Zweck |
|---|---|---|
| 2222 | TCP | SSH-Zugang |
| 8080 | TCP | lokale Webanwendungen |
| alle anderen | – | blockiert |

> **Warum Port 2222 statt 22?** Port 22 wird von automatisierten Bots permanent gescannt. Ein anderer Port reduziert das Angriffsrauschen deutlich (Security by Obscurity – kein vollständiger Schutz, aber sinnvoll).

---

### 5.2 SSH-Server

```bash
sudo apt-get install -y openssh-server

# Port idempotent auf 2222 setzen
if ! sudo grep -q "^Port 2222" /etc/ssh/sshd_config; then
    sudo sed -i 's/^#\?Port 22\b/Port 2222/' /etc/ssh/sshd_config
fi

# Nur Benutzer 'max' darf sich einloggen
grep -q "^AllowUsers max" /etc/ssh/sshd_config || \
    echo "AllowUsers max" | sudo tee -a /etc/ssh/sshd_config

sudo systemctl restart ssh
sudo systemctl enable ssh.service
sudo systemctl mask ssh.socket  # Socket-Aktivierung deaktivieren
```

**Idempotent** bedeutet: Der Code kann mehrfach ausgeführt werden, ohne Schaden anzurichten. `grep -q` prüft, ob der Eintrag schon existiert – nur wenn nicht, wird er hinzugefügt.

> **Lernpunkt:** `sed -i 's/^#\?Port 22\b/Port 2222/'`  
> `^` = Zeilenanfang, `#\?` = optionales `#` (auskommentiert), `\b` = Wortgrenze (verhindert, dass `Port 2222` selbst gematcht wird).

---

### 5.3 Browser & Desktop

**GNOME-Einstellungen via dconf:**

```bash
sudo mkdir -p /etc/dconf/db/local.d/
# Datei schreiben, dann:
sudo dconf update
```

`dconf` ist die zentrale Konfigurationsdatenbank für GNOME. Einträge in `/etc/dconf/db/local.d/` gelten systemweit und können von Benutzern nicht überschrieben werden.

Gesetzte Werte:

| Schlüssel | Wert | Effekt |
|---|---|---|
| `remember-recent-files` | `false` | Keine Datei-Historie in GNOME |
| `idle-delay` | `0` | Kein automatischer Bildschirmschoner |
| `enabled-extensions` | Liste | Nur gewünschte GNOME-Extensions aktiv |

**LibreWolf** (datenschutzfreundlicher Firefox-Fork):

```bash
sudo apt-get install -y extrepo
sudo extrepo enable librewolf
sudo apt-get install -y librewolf
```

`extrepo` verwaltet externe APT-Repositories – sicherer als manuelle `.list`-Dateien, da Signaturen automatisch geprüft werden.

---

### 5.4 Entwicklungstools

**VS Code:**

```bash
# GPG-Schlüssel importieren
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor > /tmp/packages.microsoft.gpg

# Schlüssel installieren
sudo install -D -o root -g root -m 644 \
    /tmp/packages.microsoft.gpg \
    /etc/apt/keyrings/packages.microsoft.gpg

# Repository eintragen
echo "deb [arch=amd64 signed-by=...] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list

sudo apt-get update && sudo apt-get install -y code
```

**Warum dieser Aufwand?** VS Code ist nicht in den Ubuntu-Standardrepos. Microsofts eigenes Repo wird manuell hinzugefügt – mit kryptographischer Signatur, damit APT die Pakete verifizieren kann.

Weitere Basistools:

```bash
sudo apt-get install -y wget curl git dconf-cli ca-certificates gnupg
```

---

### 5.5 Docker

Docker wird aus dem offiziellen Docker-Repository installiert (nicht aus Ubuntu-Repos, da diese oft veraltete Versionen enthalten).

```bash
# GPG-Schlüssel
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

# Ubuntu-Codename automatisch ermitteln
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

# Repository eintragen
echo "deb [arch=$(dpkg --print-architecture) signed-by=...] \
    https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list

# Installieren
sudo apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

# Benutzer zur Docker-Gruppe hinzufügen
sudo usermod -aG docker max
```

Nach dem nächsten Login kann `max` Docker ohne `sudo` nutzen.

**Installierte Komponenten:**

| Paket | Funktion |
|---|---|
| `docker-ce` | Docker Engine (Daemon) |
| `docker-ce-cli` | Kommandozeilenwerkzeug |
| `containerd.io` | Container-Laufzeitumgebung |
| `docker-buildx-plugin` | Erweitertes Image-Bauen (multi-arch) |
| `docker-compose-plugin` | `docker compose` Befehl |

---

### 5.6 Flatpak-Apps

Flatpak ist ein distributionsunabhängiges Paketformat mit Sandbox-Isolation.

```bash
sudo apt-get install -y flatpak gnome-software-plugin-flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Apps installieren
sudo -u max flatpak install -y --system flathub org.onlyoffice.desktopeditors
sudo -u max flatpak install -y --system flathub com.rabbit_company.Passky
sudo -u max flatpak install -y --system flathub com.github.Eloston.UngoogledChromium
```

| App | Paket-ID | Zweck |
|---|---|---|
| OnlyOffice | `org.onlyoffice.desktopeditors` | Office-Suite (kompatibel zu .docx/.xlsx) |
| Passky | `com.rabbit_company.Passky` | Open-Source Passwortmanager |
| Ungoogled Chromium | `com.github.Eloston.UngoogledChromium` | Chromium ohne Google-Dienste |

> `--if-not-exists` bei `flatpak remote-add` → idempotent, kein Fehler wenn Repo schon eingetragen ist.

---

### 5.7 Pausen-Erinnerung

```bash
cat <<'EOF' | sudo tee /etc/cron.d/pausenreminder
*/90 * * * * max DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    notify-send "☕ Kurze Pause?" "..." --urgency=low
EOF
```

**Cron-Syntax:** `*/90 * * * *` = alle 90 Minuten (technisch: jede Minute, deren Zahl durch 90 teilbar ist – also :00 und :30 jeder Stunde sind das nicht, daher effektiv 2× täglich um :00 und :30 – wer den genauen Rhythmus braucht, nutzt besser `systemd.timer`).

`DISPLAY=:0` und `DBUS_SESSION_BUS_ADDRESS` sind nötig, damit der Cron-Job (der ohne Grafikkontext läuft) eine Desktop-Benachrichtigung an die laufende GNOME-Session senden kann.

---

## 6. TPM 2.0 Auto-Unlock (LUKS)

Eines der komplexesten Themen im Script. Hier wird LUKS-Festplattenverschlüsselung so eingerichtet, dass beim Booten **kein Passwort eingegeben** werden muss – das TPM-Chip übernimmt das automatisch.

### Was ist LUKS?

**LUKS** (Linux Unified Key Setup) verschlüsselt eine gesamte Partition. Ohne den richtigen Schlüssel sind alle Daten unlesbar.

### Was ist TPM 2.0?

Ein **Trusted Platform Module** ist ein Sicherheitschip auf dem Mainboard. Er kann kryptographische Schlüssel speichern und nur dann herausgeben, wenn das System in einem definierten Zustand ist (gemessen über **PCR-Register**).

### PCR-Register (Platform Configuration Registers)

| PCR | Inhalt |
|---|---|
| PCR 7 | Secure Boot-Zustand |
| PCR 11 | systemd-boot Bootloader-Messung |

Das Script unterstützt zwei Modi:

| Modus | Ziel | PCR |
|---|---|---|
| **A – VM** | QEMU/KVM mit vTPM (swtpm) | PCR 7 |
| **B – Hardware** | Lenovo ThinkPad (physischer TPM) | PCR 7 + 11 |

### Ablauf im Script

```
1. Pakete installieren (clevis, tpm2-tools, cryptsetup-initramfs)
2. LUKS-Partition automatisch erkennen (blkid)
3. /etc/crypttab prüfen / anlegen
4. PCR-Zustand im TPM prüfen
5. LUKS-Passwort sicher einlesen (von /dev/tty)
6. clevis luks bind ausführen
7. Initramfs neu bauen (update-initramfs -u -k all)
8. Kontrolle: cryptsetup im initramfs vorhanden?
```

### Wichtige Pakete

| Paket | Funktion |
|---|---|
| `clevis` | Framework für automatisches LUKS-Entsperren |
| `clevis-tpm2` | TPM 2.0-Plugin für Clevis |
| `clevis-luks` | Clevis-Integration für LUKS |
| `clevis-initramfs` | Clevis-Hook für initramfs |
| `tpm2-tools` | Kommandozeilenwerkzeuge für TPM |
| `cryptsetup-initramfs` | Stellt sicher, dass cryptsetup im Boot-Image landet |

> **Kritischer Punkt:** Ohne `cryptsetup-initramfs` fehlt `cryptsetup` im initramfs → System bootet in eine Notfallshell und bleibt hängen. Das Script prüft das explizit mit `lsinitramfs`.

### Nach dem Einrichten prüfen

```bash
# Binding anzeigen
sudo clevis luks list -d /dev/sda3

# PCR-Werte lesen
sudo tpm2_pcrread sha256:7,11

# Prüfen ob cryptsetup im initramfs ist
lsinitramfs /boot/initrd.img-$(uname -r) | grep crypt
```

---

## 7. Installierte Software – Übersicht

| Software | Quelle | Kategorie |
|---|---|---|
| VS Code | Microsoft APT-Repo | Entwicklung |
| Docker CE + Compose | Docker APT-Repo | Entwicklung / Containerisierung |
| Git, curl, wget | Ubuntu Repos | Basistools |
| LibreWolf | Extrepo | Browser |
| Ungoogled Chromium | Flathub | Browser |
| OnlyOffice | Flathub | Office |
| Passky | Flathub | Sicherheit |
| QEMU / virt-manager | Ubuntu Repos | Virtualisierung |
| openssh-server | Ubuntu Repos | Fernzugriff |
| UFW | Ubuntu Repos | Firewall |
| Clevis + TPM2-Tools | Ubuntu Repos | Sicherheit / LUKS |

---

## 8. Nach dem ersten Boot – Checkliste

```bash
# Passwort ändern (PFLICHT!)
passwd

# SSH-Status prüfen
sudo systemctl status ssh

# Firewall-Status
sudo ufw status verbose

# Docker testen
docker run hello-world

# TPM-Binding prüfen
sudo clevis luks list -d /dev/$(lsblk -rno NAME,TYPE | awk '$2=="crypt"{print $1}' | head -1)

# INSTALL-STATUS lesen
cat ~/INSTALL-STATUS.txt
```

---

## 9. Wichtige Befehle zum Nachschlagen

### Systemd

```bash
systemctl status <dienst>       # Status anzeigen
systemctl start/stop <dienst>   # Starten / Stoppen
systemctl enable/disable        # Autostart an/aus
systemctl mask <dienst>         # Dienst komplett sperren
```

### APT

```bash
apt-get update                  # Paketlisten aktualisieren
apt-get install -y <paket>      # Installieren
apt-get purge <paket>           # Deinstallieren + Konfig löschen
apt-get autoremove --purge      # Verwaiste Pakete aufräumen
```

### UFW (Firewall)

```bash
ufw status verbose              # Regeln anzeigen
ufw allow 80/tcp                # Port öffnen
ufw delete allow 80/tcp         # Regel entfernen
ufw reload                      # Neu laden
```

### Docker

```bash
docker ps                       # Laufende Container
docker images                   # Lokale Images
docker compose up -d            # Stack starten
docker compose down             # Stack stoppen
docker logs <container>         # Logs anzeigen
```

### Flatpak

```bash
flatpak list                    # Installierte Apps
flatpak update                  # Alle aktualisieren
flatpak uninstall <id>          # Deinstallieren
```

---

> **Hinweis für Lernende:** Dieses Dokument beschreibt ein konkretes Deployment-Script. Viele der hier verwendeten Techniken (systemd, APT-Pinning, dconf, TPM/LUKS, Docker) sind Prüfungsrelevant für FIAE und FISI. Bei Fragen zu einzelnen Abschnitten → Trainer oder GitHub-Issues nutzen.