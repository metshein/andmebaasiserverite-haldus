# Andmebaasiserverite haldus - automaatne kontroll

Tegemist on kursuse **Andmebaasiserverite haldus** automaatkontrolli ja hindamise skriptidega.  
Tulemused kuvatakse lehel: [https://metshein.com/skripti_kontroll/db-admin.php](https://metshein.com/skripti_kontroll/db-admin.php)

## Samm 1: Kontrolli Git olemasolu

```bash
git --version
```

Kui kasku ei leitud, paigalda Git:

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

## Samm 3: Anna kaivitusoigused

```bash
chmod +x *.sh
```

## Samm 4: Kaivita esimene kontroll

```bash
./task01-check.sh
```

## Samm 5: Uuenda vajadusel skripte

```bash
git pull
```
