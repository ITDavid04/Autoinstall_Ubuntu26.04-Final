#!/bin/bash
set -e
GREEN="\033[0;32m"
BLUE="\033[0;34m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Software-Installation fuer D3023${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Netzwerk prüfen
ONLINE=false
if ping -c 1 -W 3 google.com &> /dev/null; then
    ONLINE=true
    echo -e "${GREEN}Checkmark Internet verfuegbar - Installation laeuft vollstaendig${NC}"
else
    echo -e "${YELLOW}Warnung OFFLINE-MODUS - Nur lokale Pakete verfuegbar${NC}"
fi
echo ""

# System-Anpassungen (Auto-Updates & Sudo)
echo -e "${BLUE}[SYSTEM]${NC} Auto-Updates deaktivieren & Sudo anpassen..."

# 1. Auto-Updates komplett deaktivieren
sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
sudo systemctl mask apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
sudo apt-get purge -y unattended-upgrades 2>/dev/null || true
cat <<EOF | sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
EOF

# 2. Gruppe 'sudo' anlegen und sudo ohne Passwort erlauben
sudo usermod -aG sudo max 2>/dev/null || true
echo "%sudo ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/01-admin-nopasswd > /dev/null
sudo chmod 0440 /etc/sudoers.d/01-admin-nopasswd

echo -e "${GREEN}Checkmark System-Anpassungen abgeschlossen${NC}"
echo ""

# Kernel-Parameter optimieren
echo -e "${BLUE}[SYSTEM]${NC} Kernel-Parameter optimieren..."
cat <<EOF | sudo tee /etc/sysctl.d/99-performance.conf > /dev/null
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=15
EOF
sudo sysctl -p /etc/sysctl.d/99-performance.conf
echo -e "${GREEN}Checkmark Kernel-Parameter gesetzt${NC}"
echo ""

# Debloat
echo -e "${BLUE}[DEBLOAT]${NC} Unerwuenschte Pakete entfernen..."

if command -v snap &>/dev/null && systemctl is-active --quiet snapd 2>/dev/null; then
    for SNAP_PKG in $(snap list 2>/dev/null | awk 'NR>1 {print $1}'); do
        sudo snap remove --purge "$SNAP_PKG" 2>/dev/null || true
    done
    for LOOP in $(losetup -l 2>/dev/null | awk '/snap/ {print $1}'); do
        sudo losetup -d "$LOOP" 2>/dev/null || true
    done
fi
sudo systemctl stop snapd.service snapd.socket 2>/dev/null || true
sudo systemctl disable snapd.service snapd.socket 2>/dev/null || true
sudo systemctl mask snapd.service snapd.socket 2>/dev/null || true
sudo apt-get purge -y snapd 2>/dev/null || true
sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd 2>/dev/null || true
sudo rm -f /etc/profile.d/apps-bin-path.sh 2>/dev/null || true
printf 'Package: snapd\nPin: release a=*\nPin-Priority: -1\n' | sudo tee /etc/apt/preferences.d/block-snapd > /dev/null

sudo apt-get purge -y "libreoffice*" "libobasis*" || true
for PKG in aisleriot gnome-mahjongg gnome-mines gnome-sudoku cheese rhythmbox shotwell totem firefox thunderbird; do
    dpkg -l "$PKG" &>/dev/null && sudo apt-get purge -y "$PKG" || true
done
dpkg -l | grep libreoffice | awk '{print $2}' | xargs -r sudo apt-get purge -y || true

sudo apt-get autoremove --purge -y || true
sudo apt-get clean || true
echo -e "${GREEN}Checkmark Debloat abgeschlossen${NC}"
echo ""

# Online-Installation
if [ "$ONLINE" = true ]; then
    sudo rm -f /etc/apt/preferences.d/block-linux-generic
    sudo apt-get update || true

    sudo apt-get install -y ufw
    sudo ufw allow 8080/tcp
    sudo ufw allow 2222/tcp
    sudo ufw default deny incoming
    sudo ufw --force enable

    # 1. SSH-Server installieren
    sudo apt-get install -y openssh-server

    # 2. Port sicher auf 2222 setzen (idempotent)
    if ! sudo grep -q "^Port 2222" /etc/ssh/sshd_config; then
        sudo sed -i 's/^#\?Port 22\b/Port 2222/' /etc/ssh/sshd_config
    fi

    # 3. AllowUsers ohne Duplikate hinzufügen
    grep -q "^AllowUsers max" /etc/ssh/sshd_config || echo "AllowUsers max" | sudo tee -a /etc/ssh/sshd_config

    # 4. SSH-Dienst neu starten und aktivieren
    sudo systemctl restart ssh
    sudo systemctl enable ssh.service

    # 5. Socket-Aktivierung maskieren
    sudo systemctl disable --now ssh.socket 2>/dev/null || true
    sudo systemctl mask ssh.socket 2>/dev/null || true

    sudo apt-get install -y wget curl git dconf-cli ca-certificates gnupg || true

    sudo mkdir -p /etc/dconf/db/local.d/
    printf "[org/gnome/desktop/privacy]\nremember-recent-files=false\n\n[org/gnome/desktop/session]\nidle-delay=uint32 0\n\n[org/gnome/login-screen]\ndisable-user-list=false\n" | sudo tee /etc/dconf/db/local.d/00-labor-settings
    EXTS="['tiling-assistant@ubuntu.com', 'ubuntu-dock@ubuntu.com', 'ding@rastersoft.com', 'ubuntu-appindicators@ubuntu.com']"
    printf "[org/gnome/shell]\nenabled-extensions=$EXTS\n" | sudo tee -a /etc/dconf/db/local.d/00-labor-settings
    sudo dconf update

    # LibreWolf installieren
    echo -e "${BLUE}[INSTALL]${NC} LibreWolf installieren..."
    sudo apt-get install -y extrepo
    sudo extrepo enable librewolf
    sudo extrepo update librewolf
    sudo apt-get update || true
    sudo apt-get install -y librewolf || true

    sudo apt-get install -y qemu-system-x86 virt-manager libvirt-daemon-system libvirt-clients bridge-utils || true

    sudo apt-get install -y flatpak gnome-software-plugin-flatpak || true
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
    sudo -u max flatpak install -y --system flathub org.onlyoffice.desktopeditors || true
    sudo -u max flatpak install -y --system flathub com.rabbit_company.Passky || true

    # VS Code installieren
    if ! command -v code &>/dev/null; then
        echo -e "${BLUE}[INSTALL]${NC} VS Code installieren..."
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
        sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
            | sudo tee /etc/apt/sources.list.d/vscode.list
        sudo apt-get update && sudo apt-get install -y code || true
        rm -f /tmp/packages.microsoft.gpg
    fi

    # Docker installieren
    echo -e "${BLUE}[INSTALL]${NC} Docker und Docker-Compose installieren..."
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update || true
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
    sudo groupadd docker 2>/dev/null || true
    sudo usermod -aG docker max 2>/dev/null || true
    echo -e "${GREEN}Checkmark Docker installiert und Benutzer 'max' zur Docker-Gruppe hinzugefuegt${NC}"
    echo ""

    sudo -u max flatpak install -y --system flathub com.github.Eloston.UngoogledChromium || true

    # rpi-imager ist nicht in Standard-Repos – schlägt ggf. fehl
    sudo apt-get install -y retext rpi-imager || true

    # Pausen-Erinnerung einrichten
    echo -e "${BLUE}[SYSTEM]${NC} Pausen-Erinnerung einrichten..."
    cat <<'EOF' | sudo tee /etc/cron.d/pausenreminder > /dev/null
*/90 * * * * max DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send "☕ Kurze Pause?" "Vielleicht eine gute Zeit um kurz aufzustehen!" --urgency=low
EOF
    sudo chmod 644 /etc/cron.d/pausenreminder
    echo -e "${GREEN}Checkmark Pausen-Erinnerung eingerichtet (alle 90 Min.)${NC}"
    echo ""

    cat > /home/max/FIREWALL-INFO.txt << 'FWINFO'
====================================
FIREWALL KONFIGURATION - D3023
====================================
Status: AKTIV (UFW)
OFFENE PORTS:
- Port 2222/TCP (SSH)
- Port 8080/TCP (Web/Entwicklung)
BLOECKIERT: Alle anderen eingehenden Verbindungen
WICHTIGE BEFEHLE:
Status pruefen:      sudo ufw status verbose
Port oeffnen:        sudo ufw allow PORT/tcp
Port schliessen:     sudo ufw delete allow PORT/tcp
Logs anzeigen:       sudo tail -f /var/log/ufw.log
SSH laeuft auf Port 2222 (nur Benutzer 'max')!
====================================
FWINFO
    sudo chown 1000:1000 /home/max/FIREWALL-INFO.txt

# =================================================================
# KERNEL INSTALLIEREN (Voraussetzung fuer TPM-Setup)
# =================================================================
echo -e "${BLUE}[SYSTEM]${NC} Installiere finalen Kernel..."
sudo apt-get install -y linux-generic

# =================================================================
# TPM 2.0 AUTO-UNLOCK SETUP
# =================================================================
# Hier wird LUKS so eingerichtet, dass sich die Festplatte beim
# Booten automatisch entschluesselt – ohne Passworteingabe.
#
# Es gibt zwei Modi. Genau EINEN davon aktivieren (den anderen
# auskommentieren). Standardmaessig ist Modus A aktiv.
#
# MODUS A – Virtuelle Maschine (vTPM / swtpm)
# --------------------------------------------
# Fuer Tests in QEMU/KVM mit einem emulierten TPM.
# Benutzt PCR 7 (Secure-Boot-Zustand) der sha256-Bank.
# PCR 7 ist im vTPM zuverlaessig befuellt und aendert sich
# nur, wenn Secure Boot im VM-BIOS umkonfiguriert wird.
# -> Empfohlen zum Entwickeln und Testen des Deployments.
#
# MODUS B – Echte Hardware (Lenovo ThinkPad / physischer TPM)
# ------------------------------------------------------------
# Fuer den produktiven Einsatz auf dem Zielgeraet.
# Benutzt PCR 7 (Secure Boot) + PCR 11 (Bootloader-Messung).
# Diese Kombination ist auf ThinkPads mit aktiviertem Secure
# Boot der stabilste Wert: aendert sich nicht bei Kernel-
# Updates, nur bei BIOS- oder Bootloader-Aenderungen.
# -> Erst aktivieren, wenn das Script auf der echten Hardware laeuft.
#
# VORAUSSETZUNG (beide Modi):
#   - TPM 2.0 muss im BIOS/UEFI aktiviert sein
#   - Bei vTPM: In virt-manager als "TPM 2.0 (swtpm)" eingebunden
#   - Das LUKS-Passwort muss bekannt sein (wird unten abgefragt)
#
# NACH DEM ERSTEN BOOT pruefen:
#   sudo clevis luks list -d /dev/sdX   (Binding anzeigen)
#   sudo tpm2_pcrread sha256:7,11        (PCR-Werte lesen)
# =================================================================

echo -e "${BLUE}[SYSTEM]${NC} Richte TPM 2.0 Auto-Unlock ein..."

# Alle benoetigten Pakete installieren.
# cryptsetup-initramfs sorgt dafuer, dass cryptsetup im initramfs
# landet – ohne das kann der Boot-Prozess LUKS nicht oeffnen!
sudo apt-get install -y \
    clevis \
    clevis-tpm2 \
    clevis-luks \
    clevis-initramfs \
    tpm2-tools \
    cryptsetup \
    cryptsetup-initramfs

# LUKS-Partition automatisch erkennen (erste gefundene)
LUKS_DEV=$(sudo blkid -t TYPE=crypto_LUKS -o device | head -n 1)
if [ -z "$LUKS_DEV" ]; then
    echo -e "${RED}FEHLER: Keine LUKS-Partition gefunden! TPM-Binding abgebrochen.${NC}" >&2
    exit 1
fi
echo -e "${GREEN}LUKS-Partition gefunden: $LUKS_DEV${NC}"

# -----------------------------------------------------------------
# Sicherheitscheck: Ist cryptsetup im initramfs-Hook registriert?
# -----------------------------------------------------------------
# Das ist die Ursache des "cryptsetup not found"-Fehlers beim Boot.
# Der Hook muss in /etc/crypttab eingetragen sein, sonst packt
# update-initramfs cryptsetup nicht ins Boot-Image.
LUKS_UUID=$(sudo blkid -s UUID -o value "$LUKS_DEV")
LUKS_NAME="luks-${LUKS_UUID}"

if ! grep -q "$LUKS_UUID" /etc/crypttab 2>/dev/null; then
    echo -e "${YELLOW}[TPM]${NC} crypttab-Eintrag fehlt – wird angelegt..."
    # none = kein Keyfile (Clevis uebernimmt das), luks = LUKS-Modus
    echo "${LUKS_NAME} UUID=${LUKS_UUID} none luks" | sudo tee -a /etc/crypttab
    echo -e "${GREEN}crypttab aktualisiert: ${LUKS_NAME}${NC}"
else
    echo -e "${GREEN}crypttab-Eintrag bereits vorhanden.${NC}"
fi

# Sicherheitscheck: PCR-Banks im TPM pruefen
# Gibt es sha256 und sind Werte drin (nicht nur Nullen)?
echo -e "${BLUE}[TPM]${NC} Pruefe TPM PCR-Zustand..."
if ! tpm2_pcrread sha256:7 2>/dev/null | grep -qv "0x0000000000000000000000000000000000000000000000000000000000000000"; then
    echo -e "${YELLOW}Warnung: PCR 7 (sha256) enthaelt nur Nullen oder ist nicht lesbar.${NC}"
    echo -e "${YELLOW}         Bei vTPM: VM einmal vollstaendig booten, dann Script erneut ausfuehren.${NC}"
    echo -e "${YELLOW}         Bei Hardware: Secure Boot im BIOS pruefen.${NC}"
fi

# -----------------------------------------------------------------
# LUKS-Passwort sicher abfragen (kein Klartext im Script!)
# -----------------------------------------------------------------
# Das Passwort wird nur fuer den clevis-bind-Aufruf verwendet
# und danach sofort verworfen. Es wird NICHT gespeichert.
echo ""
echo -e "${YELLOW}Bitte das aktuelle LUKS-Passwort eingeben (fuer den Clevis-Bind):${NC}"
# Passwort direkt von /dev/tty lesen – zuverlaessiger als stdin-Pipe
read -r -s -p "LUKS-Passwort: " LUKS_PASS < /dev/tty
echo ""

# =================================================================
# >> HIER EINEN DER BEIDEN MODI AUSKOMMENTIEREN <<
# =================================================================

# -----------------------------------------------------------------
# MODUS A: Virtuelle Maschine (vTPM mit swtpm)
# Aktiv fuer: Entwicklung, Tests, Deployment-Vorbereitung
# PCR 7 = Secure-Boot-Zustand (im vTPM stabil und befuellt)
# sha256 statt sha1, weil sha1 im vTPM oft leer/kaputt ist
# -----------------------------------------------------------------
#TPM_MODUS="A (VM / vTPM)"
#TPM_CONFIG='{"hash":"sha256","pcr_bank":"sha256","pcr_ids":"7"}'

# -----------------------------------------------------------------
# MODUS B: Echte Hardware – Lenovo ThinkPad (physischer TPM 2.0)
# Aktiv fuer: Produktiv-Deployment auf dem Zielgeraet
# PCR 7  = Secure Boot (aendert sich nicht bei Kernel-Updates)
# PCR 11 = systemd-boot Bootloader-Messung (extra Sicherheit)
# Secure Boot muss im ThinkPad-BIOS aktiviert sein!
# -----------------------------------------------------------------
TPM_MODUS="B (Hardware / ThinkPad)"
TPM_CONFIG='{"hash":"sha256","pcr_bank":"sha256","pcr_ids":"7,11"}'

# =================================================================
# Binding durchfuehren (gilt fuer beide Modi)
# =================================================================
echo -e "${BLUE}[TPM]${NC} Starte Clevis-Binding (Modus ${TPM_MODUS})..."

if echo "${LUKS_PASS}" | sudo clevis luks bind -d "${LUKS_DEV}" tpm2 "${TPM_CONFIG}"; then
    echo -e "${GREEN}Clevis Bind erfolgreich auf ${LUKS_DEV} angewendet.${NC}"
    echo -e "${GREEN}Modus: ${TPM_MODUS}${NC}"
    echo -e "${GREEN}Konfiguration: ${TPM_CONFIG}${NC}"
else
    echo -e "${RED}FEHLER: Clevis Bind fehlgeschlagen!${NC}" >&2
    echo -e "${RED}Moegliche Ursachen:${NC}" >&2
    echo -e "${RED}  - Falsches LUKS-Passwort${NC}" >&2
    echo -e "${RED}  - TPM nicht erreichbar (virt-manager: TPM 2.0 eingebunden?)${NC}" >&2
    echo -e "${RED}  - PCR-Bank sha256 leer (VM neu booten, dann erneut versuchen)${NC}" >&2
    echo -e "${RED}  - Bei Modus B: Secure Boot im BIOS deaktiviert${NC}" >&2
    unset LUKS_PASS
    exit 1
fi

# Passwort-Variable sicher loeschen
unset LUKS_PASS

# -----------------------------------------------------------------
# Initramfs neu bauen – RICHTIGE Reihenfolge ist wichtig!
# -----------------------------------------------------------------
# 1. Erst cryptsetup-Hook aktivieren (schreibt /etc/crypttab ins Image)
# 2. Dann clevis-Hook (haengt sich an cryptsetup dran)
# 3. Dann update-initramfs (baut das finale Image)
#
# Ohne cryptsetup-initramfs landet kein cryptsetup im Boot-Image
# -> Resultat: "cryptsetup not found" in der initramfs-Shell
# -----------------------------------------------------------------
echo -e "${BLUE}[SYSTEM]${NC} Stelle sicher dass cryptsetup-Hook aktiv ist..."
sudo dpkg-reconfigure cryptsetup-initramfs 2>/dev/null || true

echo -e "${BLUE}[SYSTEM]${NC} Aktualisiere Boot-Images (Initramfs)..."
sudo update-initramfs -u -k all

# Abschlusskontrolle: Ist cryptsetup tatsaechlich im Image?
LATEST_INITRD=$(ls -t /boot/initrd.img-* | head -n 1)
if lsinitramfs "$LATEST_INITRD" 2>/dev/null | grep -q "cryptsetup"; then
    echo -e "${GREEN}Kontrolle OK: cryptsetup ist im initramfs enthalten.${NC}"
else
    echo -e "${RED}WARNUNG: cryptsetup wurde NICHT ins initramfs aufgenommen!${NC}" >&2
    echo -e "${RED}         Beim naechsten Boot koennte LUKS nicht entsperrbar sein.${NC}" >&2
    echo -e "${RED}         Bitte manuell pruefen: lsinitramfs $LATEST_INITRD | grep crypt${NC}" >&2
fi

echo -e "${GREEN}TPM 2.0 Auto-Unlock erfolgreich eingerichtet.${NC}"
echo ""
echo -e "${YELLOW}Hinweis: Binding pruefen mit:${NC}"
echo -e "  sudo clevis luks list -d ${LUKS_DEV}"
echo ""



# =================================================================
# INSTALL-STATUS aktualisieren
# =================================================================
cat > /home/max/INSTALL-STATUS.txt << EOF
====================================
INSTALLATION ABGESCHLOSSEN
====================================
System: D3023
Benutzer: max
Modus: $( [ "$ONLINE" = true ] && echo "online" || echo "offline" )
$( [ "$ONLINE" = true ] && echo "SSH: Port 2222 (nur max)
Firewall: Aktiv
Docker: Installiert (Gruppe 'docker' aktiv fuer max)
Browser: LibreWolf & Ungoogled Chromium
Passky: Installiert
TPM 2.0: Aktiviert (Auto-Unlock, Modus ${TPM_MODUS})
Btrfs-Snapshots: Aktiviert (1x taeglich, max 3)
Pausen-Erinnerung: Aktiv (alle 90 Min.)" || echo "Keine weiteren Dienste installiert." )
Auto-Updates: Deaktiviert
Sudo: Ohne Passwort fuer Gruppe 'sudo'
Kernel-Parameter: Optimiert (swappiness=10)
====================================
EOF
sudo chown 1000:1000 /home/max/INSTALL-STATUS.txt

fi # Ende Online-Block
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Fertig!${NC}"
echo -e "${RED}WICHTIG: Passwort mit passwd aendern.${NC}"
echo -e "${GREEN}=========================================${NC}"