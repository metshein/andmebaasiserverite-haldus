# Andmebaasiserverite haldus - automaatne kontroll

Tegemist on kursuse **Andmebaasiserverite haldus** automaatkontrolli ja hindamise skriptidega.  
Tulemused kuvatakse lehel: [https://metshein.com/skripti_kontroll/db-admin.php](https://metshein.com/skripti_kontroll/db-admin.php)

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
git clone https://github.com/metshein/bash
cd bash/db_haldus
```

## Samm 3: Anna käivitusõigused

```bash
chmod +x *.sh
```

## Samm 4: Käivita esimene kontroll

```bash
./task01-check.sh
```

Kõik olemasolevad kontrollid:

- `task01-check.sh`
- `task02-check.sh`
- `task03-check.sh`
- `task04-check.sh`
- `task05-check.sh`
- `task06-check.sh`
- `task07-check.sh`

Kõigi kontrollide järjest käivitamiseks:

```bash
./run-all-checks.sh
```

## Samm 5: Uuenda vajadusel skripte

```bash
git pull
```
