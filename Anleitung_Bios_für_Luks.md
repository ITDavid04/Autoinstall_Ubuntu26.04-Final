###

Hier ist eine kurze, übersichtliche Anleitung speziell für moderne Lenovo-Geräte, um das BIOS/UEFI optimal für die automatische TPM-Verschlüsselung vorzubereiten.

### Schritt 1: Ins BIOS gelangen

1. Schalte das Lenovo-Gerät vollständig aus.
2. Schalte es ein und drücke sofort mehrfach hintereinander die **F1-Taste** (bei manchen Modellen **Fn + F1**), bis sich das BIOS/UEFI-Menü öffnet.

---

### Schritt 2: Die 3 wichtigsten Einstellungen anpassen

Navigiere mit den Pfeiltasten zu den folgenden Menüpunkten und stelle sie wie beschrieben ein:

#### 1. Security Chip (TPM 2.0) aktivieren

* **Pfad:** `Security` --> `Security Chip`
* **Einstellungen:**
* **Security Chip:** `Enabled`
* **Security Chip Selection:** `TPM 2.0` *(wird bei AMD-CPUs oft als „fTPM“ oder bei Intel als „PTT“ gelistet)*



#### 2. Secure Boot aktivieren *(Zwingend erforderlich für das automatische Entsperren)*

* **Pfad:** `Security` --> `Secure Boot`
* **Einstellungen:**
* **Secure Boot:** `Enabled`
* **Secure Boot Mode:** `Standard`


* *Hintergrund:* Nur wenn Secure Boot aktiv ist, darf der TPM-Chip den Entschlüsselungs-Key beim Systemstart automatisch freigeben.

#### 3. Reinen UEFI-Modus & OS-Optimierung erzwingen

* **Pfad:** `Startup`
* **UEFI/Legacy Boot:** `UEFI Only` *(Der alte Legacy-/CSM-Modus muss komplett aus sein)*


* **Pfad:** `Restart` (oder `Exit`)
* **OS Optimized Defaults:** `Enabled` *(Dies lädt im Hintergrund automatisch alle modernen Sicherheits- und Stromspar-Features für aktuelle Linux- und Windows-Kernel)*



---

### Schritt 3: Speichern und Booten

1. Drücke die Taste **F10** (Save and Exit).
2. Bestätige das Fenster mit **Yes** / **OK**.

Das Gerät startet nun neu. Wenn du jetzt deinen USB-Stick mit der angepassten `autoinstall.yaml` (und dem `hybrid`-Layout) ansteckst, partitioniert Ubuntu das System vollautomatisch, liest den TPM-Chip aus, verknüpft den Krypto-Key damit und verriegelt das System sicher auf deiner Hardware.