#!/bin/bash
set -e
GREEN="\033[0;32m"
BLUE="\033[0;34m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Software-Installation fuer D3001${NC}"
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
sudo usermod -aG sudo david 2>/dev/null || true 
# Berechtigung für die Gruppe 'sudo' statt 'admin'
echo "%sudo ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/01-admin-nopasswd > /dev/null
# Rechte der Datei setzen
sudo chmod 0440 /etc/sudoers.d/01-admin-nopasswd

echo -e "${GREEN}Checkmark System-Anpassungen abgeschlossen${NC}"
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
    dpkg -l | grep libreoffice | awk '{print $2}' | xargs apt-get purge -y || true
done

sudo apt-get autoremove --purge -y || true
sudo apt-get clean || true
echo -e "${GREEN}Checkmark Debloat abgeschlossen${NC}"
echo ""

# Online-Installation
if [ "$ONLINE" = true ]; then
    sudo rm -f /etc/apt/preferences.d/block-linux-generic
    sudo apt-get update
    sudo apt-get install -y linux-generic || true

    sudo apt-get install -y ufw
    sudo ufw allow 8080/tcp
    sudo ufw allow 2222/tcp
    sudo ufw default deny incoming
    sudo ufw --force enable

    # 1. SSH-Server installieren
    sudo apt-get install -y openssh-server

    # 2. Port sicher auf 2222 setzen (erwischt sowohl #Port 22 als auch Port 22)
    sudo sed -i 's/^#\?Port 22/Port 2222/' /etc/ssh/sshd_config
    
    # 3. AllowUsers hinzufügen
    echo "AllowUsers david" | sudo tee -a /etc/ssh/sshd_config

    # 4. SSH-Dienst neu starten und aktivieren
    sudo systemctl restart ssh
    sudo systemctl enable ssh.service

    # 5. Socket-Aktivierung maskieren (verhindert, dass der Socket den Port 22 wieder "kapert")
    sudo systemctl disable --now ssh.socket 2>/dev/null || true
    sudo systemctl mask ssh.socket 2>/dev/null || true

    sudo apt-get install -y wget curl git dconf-cli || true

    sudo mkdir -p /etc/dconf/db/local.d/
    printf "[org/gnome/desktop/privacy]\nremember-recent-files=false\n\n[org/gnome/desktop/session]\nidle-delay=uint32 0\n\n[org/gnome/login-screen]\ndisable-user-list=false\n" | sudo tee /etc/dconf/db/local.d/00-labor-settings
    EXTS="['tiling-assistant@ubuntu.com', 'ubuntu-dock@ubuntu.com', 'ding@rastersoft.com', 'ubuntu-appindicators@ubuntu.com']"
    printf "[org/gnome/shell]\nenabled-extensions=$EXTS\n" | sudo tee -a /etc/dconf/db/local.d/00-labor-settings
    sudo dconf update

    sudo add-apt-repository -y ppa:mozillateam/ppa || true
    printf 'Package: firefox\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n' | sudo tee /etc/apt/preferences.d/mozilla-firefox > /dev/null
    sudo apt-get update || true
    sudo apt-get install -y firefox || true

    sudo apt-get install -y qemu-system-x86 virt-manager libvirt-daemon-system libvirt-clients bridge-utils || true

    sudo apt-get install -y flatpak gnome-software-plugin-flatpak || true
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
    flatpak install -y flathub org.onlyoffice.desktopeditors || true

    if ! command -v code &>/dev/null; then
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
        sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
        sudo apt-get update && sudo apt-get install -y code || true
        rm -f /tmp/packages.microsoft.gpg
    fi

    flatpak install -y flathub com.github.Eloston.UngoogledChromium || true
    sudo apt-get install -y retext rpi-imager || true

    cat > /home/david/FIREWALL-INFO.txt << 'FWINFO'
====================================
FIREWALL KONFIGURATION - D3001
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
SSH laeuft auf Port 2222 (nur Benutzer 'david')!
====================================
FWINFO
    chown 1000:1000 /home/david/FIREWALL-INFO.txt
    echo -e "${GREEN}Online-Installation abgeschlossen.${NC}"
else
    echo -e "${YELLOW}Offline-Modus: Nur System-Anpassungen und Debloat ausgeführt.${NC}"
fi

# INSTALL-STATUS aktualisieren
cat > /home/david/INSTALL-STATUS.txt << EOF
====================================
INSTALLATION ABGESCHLOSSEN
====================================
System: D3001
Benutzer: david
Modus: $( [ "$ONLINE" = true ] && echo "online" || echo "offline" )
$( [ "$ONLINE" = true ] && echo "SSH: Port 2222 (nur david)
Firewall: Aktiv" || echo "Keine weiteren Dienste installiert." )
Auto-Updates: Deaktiviert
Sudo: Ohne Passwort für Gruppe 'admin'
====================================
EOF
chown 1000:1000 /home/david/INSTALL-STATUS.txt

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Fertig!${NC}"
echo -e "${RED}WICHTIG: Passwort mit passwd aendern.${NC}"