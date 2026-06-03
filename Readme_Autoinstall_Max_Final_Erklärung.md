
# 🚀 Ubuntu 26.04 Autoinstall – Vollautomatische Systembereitstellung

Diese Dokumentation erklärt die **autoinstall.yaml** für eine vollautomatische Installation von Ubuntu 26.04 Desktop (minimal). Sie richtet sich an Umschüler der Fachrichtungen Anwendungsentwicklung und Systemintegration und vermittelt nicht nur das *Was*, sondern vor allem das *Warum* jedes einzelnen Schrittes.

---

## 📋 Überblick über den Ablauf

Die Automatisierung läuft in vier Phasen ab – von der Vorbereitung des Installers bis zum fertig eingerichteten Entwickler-System.

| Phase           | Werkzeug                        | Hauptaufgabe                                                                                                          |
| :-------------- | :------------------------------ | :-------------------------------------------------------------------------------------------------------------------- |
| **Early**       | Bash (Host-System)              | Fake-APT-Wrapper bereitstellen, Kernel-Fehler blockieren – für eine stabile Offline-/Labor-Installation.              |
| **Basis**       | Subiquity / Curtin              | Partitionierung (LUKS/LVM), Basissystem aufsetzen, Benutzer `max` anlegen, temporäre Passwörter setzen.              |
| **Late**        | `curtin in-target`              | GRUB-Tweaks, Base64-Skript ablegen, Passwort-Reset erzwingen, Terminal-Alias einrichten.                              |
| **Post-Install**| `install-software.sh` (per `run`)| Snap-Debloat, Docker/VS-Code installieren, TPM-Anbindung (Clevis) konfigurieren, Kernel finalisieren.                  |

---

## ⚙️ Die autoinstall.yaml im Detail

### 🌍 Grundkonfiguration

- **source: ubuntu-desktop-minimal** – minimale Desktop-Variante ohne Bürosoftware und Spiele.
- **identity** – legt Rechnername (`hostname`) und Benutzer `max` an. Das Passwort wird als **yescrypt-Hash** gesetzt (hier `1234`, muss später geändert werden!).
- **locale, keyboard, timezone** – System auf Deutsch und Berliner Zeitzone.
- **storage: lvm, encrypted: true** – gesamte Platte wird mit **LUKS** verschlüsselt und mit **LVM** flexibel partitioniert. Das temporäre LUKS-Passwort steht im Klartext – nur so läuft die Installation ohne manuelle Eingabe durch.

---

### 🔧 Early Commands – Tricks noch während der Installation

```bash
rm -f /run/kernel-meta-package
touch /run/kernel-meta-package
```

Eine leere Datei gaukelt dem Installer vor, ein Kernel-Metapaket sei bereits vorhanden. Das verhindert einen Paketquellen-Fehler in Offline-Szenarien.

#### 🎭 Der Fake-APT-Wrapper

```bash

# Gekürztes Prinzip:
if [[ "$*" == *"--download-only"* && "$*" == *"install"* ]]; then
    echo "Offline-Installation: --download-only abgefangen" >&2
    exit 0
fi
if [[ "$*" == *"linux-generic"* ]]; then
    echo "linux-generic wird später installiert" >&2
    exit 0
fi
exec /usr/bin/apt-get "$@"
```

**Warum dieser Hack?**  
Ubuntu 24.04 nutzt den Subiquity-Installer. Dieser versucht **auch bei reiner Offline-Konfiguration** während der Installation Pakete und Kernel-Updates aus dem Internet nachzuladen – was in Laborumgebungen ohne Netzwerk unweigerlich zum Abbruch führt. Das Skript fängt genau diese kritischen Aufrufe ab und antwortet mit Erfolg, ohne wirklich etwas zu tun. Die Installation von `linux-generic` wird auf später verschoben, um Konflikte zu vermeiden.  
Für angehende Fachinformatiker ist das ein perfektes Beispiel dafür, wie man widerspenstige Installer durch intelligente Shell-Skripte zähmt.

---

### 🧰 Late Commands – Feinschliff vor dem ersten Boot

Jeder Befehl beginnt mit `curtin in-target --` und wird **im installierten System** ausgeführt.

| Schritt | Befehl / Inhalt                                      | Erklärung                                                                                                                                                    |
| :------ | :--------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1       | `block-kdump` per APT-Pinning                        | Das Paket `kdump-tools` (Kernel-Absturzanalyse) wird dauerhaft blockiert – spart Ressourcen.                                                                |
| 2       | `locale-gen`, `update-locale`, Tastatur anpassen     | Stellt sicher, dass das System **vollständig auf Deutsch** eingestellt bleibt.                                                                               |
| 3       | GRUB: `split_lock_detect=off`                        | Deaktiviert eine störende CPU-Warnung auf vielen Intel-Prozessoren (vor allem Lenovo ThinkPads).                                                             |
| 4       | `update-initramfs -u`                                | Baut das **initramfs** neu – essentiell, damit die LUKS-Entschlüsselung und alle Treiber beim Booten bereitstehen.                                          |
| 5       | `apt-get clean`                                      | Löscht den APT-Cache, spart Platz.                                                                                                                           |
| 6       | `chage -d 0 max`                                     | Setzt das Passwort-Änderungsdatum auf 1970 → **erzwingt eine sofortige Passwortänderung** beim ersten Login.                                                 |
| 7       | **Base64-Dekodierung** → `/home/max/install-software.sh` | Das große Nachinstallations-Skript wird auf die Platte gelegt (ausführbar, gehört Benutzer `max`). **Es startet nicht automatisch!**                         |
| 8       | Alias `run` + Begrüßungsbanner in `.bashrc`          | Im Terminal erscheint beim ersten Öffnen ein Hinweis, dass mit dem Befehl `run` die gesamte Entwickler-Software installiert werden kann.                     |
| 9       | `README-INSTALLATION.txt` auf dem Desktop            | Eine Textdatei erinnert auch grafisch an die nächsten Schritte.                                                                                              |
| 10      | Löschen des Fake-APT-Wrappers                        | Jetzt ist das echte `apt-get` wieder verfügbar.                                                                                                              |

---

## 🚀 Das Postinstall-Skript – `install-software.sh`

Das Skript wird durch den Befehl **`run`** (bzw. `sudo bash /home/max/install-software.sh`) gestartet. Es führt die folgenden Aufgaben aus:

### 🔍 Internetcheck

Zu Beginn prüft das Skript, ob eine Verbindung zu `google.com` möglich ist. Danach richten sich die folgenden Aktionen:

- **Online** → alle Tools werden aus dem Internet nachinstalliert.
- **Offline** → nur lokale Optimierungen werden durchgeführt.

### 🛠️ System-Anpassungen

- **Automatische Updates komplett deaktivieren** (`apt-daily.timer`, `unattended-upgrades`).
- **sudo ohne Passwort** für Benutzer `max` (Gruppe `sudo`).
- Kernel-Parameter optimieren (`vm.swappiness=10`, etc.).

> ### ⚠️ Sicherheitshinweis: Labor vs. Produktion
>
> **sudo ohne Passwort** und **deaktivierte Updates** sind **nur in einer geschützten Labor- oder Schulungsumgebung** sinnvoll. Auf einem produktiven Firmenrechner wäre das ein erhebliches Sicherheitsrisiko!  
> Im realen Einsatz müssen Sicherheitsupdates automatisiert und sudo auf einzelne Befehle beschränkt werden.

### 🧹 Debloat

- Snap vollständig deinstallieren (Firefox, Software-Center etc.).
- LibreOffice, Spiele und andere unnötige Pakete löschen.
- Abschließend `autoremove --purge` und `clean`.

### 🌐 Online-Installationen (nur wenn Internet)

- **Firewall UFW** einrichten: erlaubt Ports `8080/tcp` und `2222/tcp`, blockiert alle eingehenden Verbindungen.
- **SSH-Server** installieren, auf **Port 2222** umstellen, Zugriff nur für Benutzer `max`.
- Basiswerkzeuge: `wget`, `curl`, `git`, `dconf-cli`, `gnupg`.
- **Desktop-Anpassungen** (Gnome-Extensions, Verlauf deaktivieren).
- **Browser**: LibreWolf und Ungoogled Chromium (Flatpak).
- **Virtualisierung**: QEMU/KVM, Virt-Manager.
- **Passwortmanager**: KeePassXC (Flatpak).
- **Office**: OnlyOffice DesktopEditoren (Flatpak).
- **VS Code** aus offiziellem Microsoft-Repository.
- **Docker & Docker Compose** – Benutzer `max` wird der Gruppe `docker` hinzugefügt.
- **Pausen-Erinnerung** per Cronjob (alle 90 Minuten eine Desktop-Benachrichtigung).
- Abschließend eine `FIREWALL-INFO.txt` mit allen offenen Ports.

### 🔐 TPM 2.0 Auto-Unlock (Clevis)

Nach der Software-Installation wird der **automatische LUKS-Entsperrvorgang** eingerichtet – ohne Passworteingabe beim Booten.

1. **Benötigte Pakete:** `clevis`, `clevis-tpm2`, `clevis-luks`, `clevis-initramfs`, `tpm2-tools`, `cryptsetup-initramfs`.
2. Die LUKS-Partition wird automatisch erkannt.
3. Das **aktuelle LUKS-Passwort** wird einmalig abgefragt (nicht gespeichert!).
4. Je nach Hardware wird ein **Bind** mit dem TPM-Chip erstellt:
   - **Modus A (VM)** – PCR 7 (Secure Boot), sha256-Bank.
   - **Modus B (Echte Hardware, z. B. Lenovo ThinkPad)** – PCR 7 + PCR 11 (Bootloader-Messung).
5. Nach erfolgreicher Bindung wird das **initramfs neu gebaut**, damit Clevis und cryptsetup beim Booten verfügbar sind.

> **Wichtiger Hinweis für Systemintegratoren (Modus B mit PCR 11):**  
> PCR 11 misst den Zustand des Bootloaders (GRUB). Nach jedem Kernel-Update oder einer GRUB-Änderung **ändert sich dieser Wert – das Auto-Unlock scheitert dann!**  

> Die Lösung ist ein erneuter Bind mit dem aktuellen PCR-Wert, z. B.:

> ```bash
> sudo clevis luks bind -d /dev/nvme0n1p3 tpm2 '{"pcr_ids":"7,11"}'
> ```

> **Wichtig:** Der Befehl wird auf die **LUKS-Partition** (z. B. `/dev/sda3`, `/dev/nvme0n1p3`) angewendet – nicht auf die ganze Platte!  

> Im Produktivbetrieb sollte dieser Schritt als Hook nach Kernel-Updates automatisiert werden.

Das Skript endet mit einer Kontrolle, ob `cryptsetup` im initramfs enthalten ist, und einer Zusammenfassung in `/home/max/INSTALL-STATUS.txt`.

---

## 🏁 Ergebnis und nächste Schritte

1. **Erster Boot** – LUKS wird (dank TPM) automatisch entsperrt; das System startet durch.
2. **Benutzer `max`** muss beim ersten Login ein **neues Passwort** vergeben.
3. Ein Terminal-Banner und eine Textdatei auf dem Desktop erinnern daran, den Befehl **`run`** auszuführen.
4. Nach erfolgreichem Durchlauf von `install-software.sh` ist das System vollständig eingerichtet und optimiert:
   - Entwicklerwerkzeuge (Docker, VS Code, Git)
   - sichere Browser, Passwortmanager, Virtualisierung
   - gehärteter SSH-Zugang auf Port 2222
   - Firewall aktiv
   - TPM-basierte Festplattenentsperrung

---

## 💡 Für Auszubildende besonders lehrreich

- **Cloud-Init / Autoinstall** als moderne Automatisierungsmethode verstehen.
- **LUKS-Verschlüsselung und TPM-Entsperrung** praktisch anwenden.
- **Shell-Scripting** in der Praxis: Fake-APT, Base64-Einbettung, Schleifen, Fallunterscheidungen.
- **Systemanpassungen** auf Profi-Niveau: GRUB-Parameter, Kernel-Tuning, Debloat.
- **Paketmanagement** über apt, extrepo und Flatpak.
- **Container & Virtualisierung** mit Docker und QEMU/KVM.
- **Sicherheitsabwägungen**: Zielkonflikt zwischen Komfort und Härtung.

---

## ⚠️ Zusammenfassung Sicherheitshinweise

| Einstellung                     | Risiko                                                                 | Empfehlung für Produktivumgebung                          |
| :------------------------------ | :--------------------------------------------------------------------- | :-------------------------------------------------------- |
| **sudo ohne Passwort**          | Jeder Prozess des Benutzers hat Admin-Rechte.                         | Nur für Labor/Test. Sonst sudo auf einzelne Befehle begrenzen. |
| **Auto-Updates deaktiviert**    | Keine Sicherheits-Patches, System wird schnell angreifbar.             | Sicherheitsupdates automatisch einspielen (z. B. `unattended-upgrades`). |
| **LUKS-Passwort im Klartext**   | Nur während der Installation genutzt, muss **sofort geändert werden**! | Nach Installation LUKS-Passwort ändern (`cryptsetup luksChangeKey`). |

> **Merke:** Diese Konfiguration ist für eine reproduzierbare Laborumgebung optimiert. Vor dem Einsatz in der Praxis müssen die Sicherheitseinstellungen an die Unternehmensrichtlinien angepasst werden.
