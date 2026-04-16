# Andmebaasiserverite haldus - automaatne kontroll

Tegemist on kursuse **Andmebaasiserverite haldus** automaatkontrolli ja hindamise skriptidega.  
Tulemused kuvatakse lehel: [http://localhost/skripti_kontroll/db-admin.php](http://localhost/skripti_kontroll/db-admin.php)

## Samm 1: Kontrolli Git olemasolu

```bash
git --version
```

Kui käsku ei leitud, paigalda Git:

```bash
# Ubuntu / Debian / Raspberry Pi OS
sudo apt update
sudo apt install -y git

# Fedora
sudo dnf install -y git

# Arch
sudo pacman -S git
```

## Samm 2: Lae alla skriptid

```bash
git clone https://github.com/metshein/andmebaasiserverite-haldus dbhaldus
cd dbhaldus
```

## Samm 3: Anna käivitusõigused

```bash
chmod +x *.sh
```

## Samm 4: Käivita esimene kontroll

```bash
./task01-check.sh
```

Kui jooksutad kontrolli teisest masinast (nt Raspberry Pi), sea endpoint faili `server.conf` (skript loeb selle automaatselt):

```bash
http://YOUR_PC_IP/skripti_kontroll/api/db-submit.php
```

Alternatiivina saad URL-i anda jooksvalt:

```bash
SERVER_URL="http://YOUR_PC_IP/skripti_kontroll/api/db-submit.php" ./task01-check.sh
```

## Samm 5: Uuenda vajadusel skripte

```bash
git pull
```
