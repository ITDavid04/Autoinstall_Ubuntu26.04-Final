# 🖥️ Ubuntu 26.04 Autoinstall – D3001

> Automatische Erstinstallation von Ubuntu Desktop für den Schulungsrechner **D3001**  
> Umschulung IT-Systemintegration · Klasse 2026

---

## 📋 Was macht dieses Projekt?

Dieses Projekt enthält eine **Autoinstall-Konfiguration** für Ubuntu.  
Damit wird Ubuntu vollautomatisch installiert – ohne dass jemand auf „Weiter" klicken muss.

Nach der Installation startet der Benutzer `david` das erste Mal den Rechner, öffnet ein Terminal und gibt **einen einzigen Befehl** ein – der Rest passiert automatisch.

---

## 📁 Dateien im Repo

```
.
├── user-data          # Die Autoinstall-Konfiguration (cloud-init Format)
├── meta-data          # Pflichtdatei für cloud-init (darf leer sein)
├── postinstall.sh     # Skript, das nach dem ersten Login ausgeführt wird
└── README.md          # Diese Datei
```

---

## ⚙️ Was passiert bei der Installation?

Die Installation läuft in **drei Phasen**:

### Phase 1 – Autoinstall (`user-data`)

Der Installer richtet automatisch ein:

| Was | Einstellung |
|-----|-------------|
| Hostname | `D3001` |
| Benutzername | `david` |
| Sprache / Tastatur | Deutsch (de_DE) |
| Zeitzone | Europe/Berlin |
| Festplatte | Größte verfügbare Disk, GPT, mit LVM |
| SSH-Server | Nicht vorinstalliert (wird später nachgeholt) |

**Partitionierung:**

```
[EFI]  1 GB   → /boot/efi  (FAT32)
[BOOT] 1 GB   → /boot       (ext4)
[LVM]  Rest   → ubuntu-vg / root (ext4)
```

### Phase 2 – `late-commands` (läuft noch im Installer)

Direkt nach der Installation, bevor der Rechner neu startet:

- 🌍 Sprache und Tastaturlayout werden finalisiert (`de_DE.UTF-8`)
- 🔧 GRUB-Parameter werden gesetzt (`split_lock_detect=off`)
- 🔄 Initramfs wird neu gebaut
- 🔐 Benutzer `david` muss beim ersten Login das Passwort ändern (`chage -d 0`)
- 📜 Das Postinstall-Skript wird als Base64 ins System kopiert
- 💬 Ein Hinweis-Banner wird in `.bashrc` eingetragen

### Phase 3 – `install-software.sh` (läuft nach dem ersten Login)

Das Skript erkennt automatisch, ob Internet vorhanden ist:

**Ohne Internet (Offline-Modus):**

- Bloatware entfernen (Snap, LibreOffice, Spiele, Firefox-Snap, ...)
- Auto-Updates deaktivieren
- Sudo ohne Passwort konfigurieren

**Mit Internet (Online-Modus, zusätzlich):**

- 🔒 Firewall (UFW) aktivieren → Port 2222 (SSH) und 8080 (Web) offen
- 🔑 SSH-Server installieren, auf Port **2222** konfigurieren
- 🦊 Firefox (echtes .deb aus Mozilla-PPA, nicht Snap)
- 💻 VS Code
- 📦 Flatpak + Flathub
- 📝 OnlyOffice (via Flatpak)
- 🌐 Ungoogled Chromium (via Flatpak)
- 🖥️ QEMU/KVM + Virt-Manager (Virtualisierung)
- 🍓 Raspberry Pi Imager
- 📄 ReText (Markdown-Editor)

---

## 🚀 Wie benutze ich das?

### 1. Repo klonen

```bash
git clone https://github.com/Wiki-BlueMarlin/Autoinstall_Ubuntu26.04-Final
cd Autoinstall_Ubuntu26.04-Final
```

---

### 2. Postinstall-Skript anpassen und kodieren

> ⚠️ **Wichtig:** Wenn `postinstall.sh` verändert wird, muss es **neu kodiert** und in `user-data` **neu eingefügt** werden. Sonst wird die alte Version installiert!

**Schritt 1 – Skript kodieren:**

Einen Ordner anlegen, `postinstall.sh` dort ablegen, dann im Terminal:

```bash
# Rechtsklick auf den Ordner → "Im Terminal öffnen"
base64 -w0 postinstall.sh > postinstall.b64
```

Die Datei `postinstall.b64` erscheint danach im selben Ordner.  
Inhalt mit einem Texteditor öffnen und den gesamten String kopieren.

**Schritt 2 – String in `user-data` einfügen:**

In `user-data` den folgenden Block suchen (Schritt 6 in den `late-commands`):

```yaml
# 5. Postinstall-Skript ablegen (Base64-kodiert)
    - |
      curtin in-target -- bash -c 'echo "HIER_DEIN_BASE64_STRING" | base64 -d > /home/david/install-software.sh && chmod +x /home/david/install-software.sh && chown 1000:1000 /home/david/install-software.sh'
      
 **Achtung!!! Namen Korregieren im Pfad!!!  /home/davi/install-software.sh &&   --->>> Auf deinen Namen    

# 5. Postinstall-Skript ablegen (Base64-kodiert)
    # WICHTIG: String neu generieren mit: base64 -w 0 install-software.sh
    - |
      curtin in-target -- bash -c 'echo "HIER_DEIN_BASE64_STRING" | base64 -d > /home/max/install-software.sh && chmod +x /home/max/install-software.sh && chown 1000:1000 /home/max/install-software.sh'

`HIER_DEIN_BASE64_STRING` durch den kopierten Inhalt aus `postinstall.b64` ersetzen.  
⚠️ Der String muss **innerhalb der Anführungszeichen** stehen – also zwischen `echo "` und `" |`.

Danach speichern.

---

### 3. ISO mit Cubic vorbereiten

Die Autoinstall-Konfiguration wird mit **[Cubic](https://launchpad.net/cubic)** (Custom Ubuntu ISO Creator) in ein Standard-Ubuntu-ISO eingebettet.

**Cubic installieren (einmalig):**
```bash
sudo apt-add-repository ppa:cubic-wizard/release
sudo apt update
sudo apt install cubic
```

**Vorgehen in Cubic:**

1. Ubuntu-ISO öffnen: `ubuntu-26.04.0-2026.05.05-desktop-amd64.iso`

2. Im Reiter **Preseed** die Dateien `user-data` und `meta-data` einfügen

3. Im Reiter **Boot** die `grub.cfg` anpassen (siehe Repo-Datei `grub.cfg`)

4. **Kernel bleibt Standard** – kein `linux-generic` auswählen

5. ISO generieren lassen

---

### 4. USB-Stick vorbereiten

Zuerst herausfinden, welches Gerät der USB-Stick ist:

```bash
lsblk
# Listet alle Laufwerke auf – USB-Stick z.B. /dev/sdb
```

Dann das fertige ISO auf den Stick schreiben:

```bash
sudo dd if=ubuntu-autoinstall.iso of=/dev/sdX bs=4M status=progress
# ⚠️  /dev/sdX durch das richtige Gerät ersetzen – falsch = Datenverlust!
sync
```

> 💡 Alternativ funktioniert auch **Raspberry Pi Imager** oder ein anderes ISO-Schreibprogramm.

---

### 5. Von USB booten und warten

Den Zielrechner vom USB-Stick starten.  
Die Installation läuft vollautomatisch durch (~10–20 Minuten, je nach Hardware).

---

### 6. Nach dem ersten Login: Software installieren

```bash
run
# Das ist ein Alias für: sudo bash ~/install-software.sh
```

Passwort direkt danach ändern: Das Passwort wird beim ersten Boot erzwungen also kannst du diesen Schritt überspringen.

```bash
passwd
```

---

## 🔐 Sicherheitshinweise

> ⚠️ **Das Standard-Passwort `1234` muss beim ersten Login geändert werden.**  
> Das System erzwingt dies automatisch.

```bash
# Passwort manuell ändern
passwd
```

SSH läuft auf **Port 2222** (nicht dem Standard-Port 22):

```bash
# Von einem anderen Rechner verbinden
ssh -p 2222 xyz@IP-ADRESSE

```

## Nur DU Hast ZUgriff mit Passwort / Wenn dir das zu unsicher ist ändere das Vorgehen.

---

## 🔩 Technische Details

### Was ist Base64 und warum wird es verwendet?

Das Postinstall-Skript wird **Base64-kodiert** in die `user-data` eingebettet.

**Warum?**  
YAML (das Format von `user-data`) mag keine Sonderzeichen wie `$`, `"`, `'` oder Zeilenumbrüche innerhalb von Strings. Das Skript enthält viele davon. Base64 wandelt beliebige Inhalte in einen sicheren, einzeiligen String um.

```bash
# Skript kodieren (vor dem Einbetten):
base64 -w0 postinstall.sh > postinstall.b64

# -w0 bedeutet: keine automatischen Zeilenumbrüche (wichtig!)
# Das Ergebnis ist ein langer, einzeiliger Text

# Skript wieder dekodieren (so macht es der Installer):
base64 -d postinstall.b64 > postinstall.sh
```

### Was ist LVM?

LVM (Logical Volume Manager) ist eine Abstraktionsschicht über Festplattenpartitionen.

```
Physische Disk
└── LVM Physical Volume (lvm-pv)
    └── Volume Group: ubuntu-vg
        └── Logical Volume: root  →  /
```

**Vorteil:** Partitionsgrößen können später ohne Neuinstallation verändert werden.

### Was ist `curtin in-target`?

`curtin` ist das Installations-Backend von Ubuntu. `in-target` führt Befehle im **neu installierten System** aus (nicht im Live-Installer-System).

```bash
# Beispiel:
curtin in-target -- apt-get install -y vim
# → installiert vim im Zielsystem, nicht im Installer
```

### Was macht `split_lock_detect=off`?

Einige ältere oder günstigere CPUs verursachen beim Zugriff auf geteilten Speicher einen „split lock". Linux 5.8+ bricht dann mit einem Fehler ab. `split_lock_detect=off` deaktiviert diese Prüfung – nötig für manche Schulungsrechner.

---

## 📊 Überblick: Was wird installiert / entfernt?

| Aktion | Paket/Dienst | Begründung |
|--------|-------------|------------|
| ❌ Entfernt | Snap + alle Snap-Pakete | Overhead, Firefox-Snap zu langsam |
| ❌ Entfernt | LibreOffice | Ersatz: OnlyOffice via Flatpak |
| ❌ Entfernt | Gnome-Spiele (Mahjongg, Mines, Sudoku) | Nicht benötigt |
| ❌ Entfernt | Rhythmbox, Shotwell, Totem | Nicht benötigt |
| ❌ Entfernt | Auto-Updates | Manuell kontrolliert im Schulungsumfeld |
| ✅ Installiert | Firefox (.deb) | Schneller als Snap-Version |
| ✅ Installiert | VS Code | Entwicklungsumgebung |
| ✅ Installiert | QEMU/KVM + Virt-Manager | Virtualisierung |
| ✅ Installiert | OnlyOffice | Office-Suite |
| ✅ Installiert | Flatpak + Flathub | App-Store |
| ✅ Installiert | OpenSSH (Port 2222) | Fernzugriff |
| ✅ Installiert | UFW Firewall | Grundschutz |

---

## 🧩 Glossar

| Begriff | Erklärung |
|---------|-----------|
| **cloud-init** | Standard-Format zur automatischen Systemkonfiguration beim ersten Start |
| **Autoinstall** | Ubuntu-Erweiterung von cloud-init für die unbeaufsichtigte Installation |
| **YAML** | Menschenlesbares Datenformat (wie JSON, aber mit Einrückungen) |
| **LVM** | Logical Volume Manager – flexible Festplattenverwaltung |
| **UFW** | Uncomplicated Firewall – einfache Firewall-Verwaltung für Linux |
| **Flatpak** | Universelles App-Paketformat, unabhängig von der Distribution |
| **Base64** | Kodierungsverfahren: wandelt beliebige Daten in ASCII-Text um |
| **curtin** | Installations-Backend des Ubuntu Subiquity-Installers |
| **Snap** | Canonical's eigenes App-Paketformat (hier bewusst entfernt) |
| **PPA** | Personal Package Archive – inoffizielles APT-Repository |

---

## 👥 Autoren

Erstellt im Rahmen der Umschulung zum IT-Systemintegrator  
📅 2024/2025

---

*Fragen? Einfach im Kurs ansprechen oder ein Issue im Repo öffnen!*
*Lese die INFO_WICHTIG.md*
