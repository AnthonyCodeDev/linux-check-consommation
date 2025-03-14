#!/bin/bash

dependencies=(lscpu lsblk dmidecode lspci bc free xrandr lsusb)
for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        echo "❌ Dépendance manquante : $dep. Installez-la avec : sudo apt install -y $dep"
        exit 1
    fi
done

# Demande à l'utilisateur le nombre d'heures actives par jour
read -p "Combien de temps est actif votre système ? (0-24): " user_active_hours
if ! [[ "$user_active_hours" =~ ^[0-9]+$ ]] || [ "$user_active_hours" -gt 24 ]; then
    echo "Entrée invalide. Veuillez entrer un nombre entier entre 0 et 24."
    exit 1
fi
active_hours=$user_active_hours
idle_hours=$((24 - active_hours))
psu_efficiency=0.87

# Détection du type de système à partir du chassis-type (nécessite les droits root)
system_type=$(sudo dmidecode -s chassis-type 2>/dev/null)
if [ -z "$system_type" ]; then
    system_type="Système Inconnu"
fi
if [ "$system_type" == "Other" ]; then
    if [ -f /sys/class/dmi/id/product_name ]; then
        system_type=$(cat /sys/class/dmi/id/product_name)
    fi
fi

# Pour un PC de bureau/gaming, on augmente certains coefficients.
if [[ "$system_type" == *"Desktop"* || "$system_type" == *"Tower"* || "$system_type" == *"Gaming"* || "$system_type" == *"PC de bureau"* ]]; then
    cpu_active_multiplier=0.70
    cpu_idle_multiplier=0.20
    gpu_active_multiplier=0.90
    gpu_idle_multiplier=0.30
    mb_active=25
    mb_idle=15
    screen_active=30
else
    cpu_active_multiplier=0.30
    cpu_idle_multiplier=0.05
    gpu_active_multiplier=0.50
    gpu_idle_multiplier=0.10
    mb_active=15
    mb_idle=10
    screen_active=15
fi

# QUI: Vergeylen Anthony
# QUAND: 13/03/2025
# QUOI: Calcule la consommation quotidienne du CPU en kWh en utilisant le TDP et des coefficients d'utilisation.
# Arguments: Aucun
# Sortie: Consommation du CPU en kWh (string)
get_cpu_consumption() {
    tdp=$(sudo dmidecode -t processor 2>/dev/null | grep -m1 "TDP" | awk '{print $3}')
    if [ -z "$tdp" ]; then
        cpu_model=$(lscpu | grep "Model name:" | sed 's/Model name:\s*//')
        if [[ "$cpu_model" == *"i9"* || "$cpu_model" == *"Ryzen 9"* ]]; then
            tdp=95
        elif [[ "$cpu_model" == *"i7"* || "$cpu_model" == *"Ryzen 7"* ]]; then
            tdp=85
        elif [[ "$cpu_model" == *"i5"* || "$cpu_model" == *"Ryzen 5"* ]]; then
            tdp=65
        elif [[ "$cpu_model" == *"i3"* || "$cpu_model" == *"Ryzen 3"* ]]; then
            tdp=45
        else
            tdp=50
        fi
    fi
    active_consumption=$(echo "scale=2; $tdp * $cpu_active_multiplier" | bc)
    idle_consumption=$(echo "scale=2; $tdp * $cpu_idle_multiplier" | bc)
    daily_wh=$(echo "scale=2; ($active_consumption * $active_hours) + ($idle_consumption * $idle_hours)" | bc)
    cpu_kwh=$(echo "scale=3; $daily_wh / 1000" | bc)
    echo "$cpu_kwh"
}

# QUI: Vergeylen Anthony
# QUAND: 13/03/2025
# QUOI: Calcule la consommation quotidienne du GPU en kWh en détectant le type de GPU et en appliquant des coefficients d'utilisation.
# Arguments: Aucun
# Sortie: Consommation du GPU en kWh (string)
get_gpu_consumption() {
    gpu_info=$(lspci | grep -i "VGA\|3D")
    if [[ -z "$gpu_info" ]]; then
        echo "0"
        return
    fi
    if echo "$gpu_info" | grep -qi "NVIDIA"; then
        if echo "$gpu_info" | grep -qi "GeForce"; then
            tdp_gpu=200
        else
            tdp_gpu=50
        fi
    elif echo "$gpu_info" | grep -qi "AMD"; then
        tdp_gpu=200
    elif echo "$gpu_info" | grep -qi "Intel"; then
        tdp_gpu=25
    else
        tdp_gpu=100
    fi
    active_consumption=$(echo "scale=2; $tdp_gpu * $gpu_active_multiplier" | bc)
    idle_consumption=$(echo "scale=2; $tdp_gpu * $gpu_idle_multiplier" | bc)
    daily_wh=$(echo "scale=2; ($active_consumption * $active_hours) + ($idle_consumption * $idle_hours)" | bc)
    gpu_kwh=$(echo "scale=3; $daily_wh / 1000" | bc)
    echo "$gpu_kwh"
}

# QUI: Vergeylen Anthony
# QUAND: 13/03/2025
# QUOI: Retourne la consommation quotidienne estimée pour la carte mère et le chipset en kWh.
# Arguments: Aucun
# Sortie: Consommation de la carte mère en kWh (string)
get_motherboard_consumption() {
    daily_wh=$(echo "scale=2; ($mb_active * $active_hours) + ($mb_idle * $idle_hours)" | bc)
    mb_kwh=$(echo "scale=3; $daily_wh / 1000" | bc)
    echo "$mb_kwh"
}

# QUI: Vergeylen Anthony
# QUAND: 13/03/2025
# QUOI: Calcule la consommation quotidienne de la RAM en kWh en se basant sur la quantité totale de mémoire.
# Arguments: Aucun
# Sortie: Consommation de la RAM en kWh (string)
get_ram_consumption() {
    total_ram_mb=$(free -m | awk '/Mem:/ {print $2}')
    total_ram_gb=$(echo "scale=2; $total_ram_mb / 1024" | bc)
    active_rate=0.5
    idle_rate=0.3
    active_wh=$(echo "scale=2; $total_ram_gb * $active_rate * $active_hours" | bc)
    idle_wh=$(echo "scale=2; $total_ram_gb * $idle_rate * $idle_hours" | bc)
    daily_wh=$(echo "scale=2; $active_wh + $idle_wh" | bc)
    ram_kwh=$(echo "scale=3; $daily_wh / 1000" | bc)
    echo "$ram_kwh"
}

# QUI: Vergeylen Anthony
# QUAND: 13/03/2025
# QUOI: Calcule la consommation quotidienne des dispositifs de stockage (SSD et HDD) en kWh.
# Arguments: Aucun
# Sortie: Consommation des dispositifs de stockage en kWh (string)
get_storage_consumption() {
    ssd_list=$(lsblk -d -o NAME,ROTA | awk '$2=="0" {print $1}' | paste -sd ', ' -)
    hdd_list=$(lsblk -d -o NAME,ROTA | awk '$2=="1" {print $1}' | paste -sd ', ' -)
    ssd_count=$(echo "$ssd_list" | awk -F', ' '{print NF}')
    hdd_count=$(echo "$hdd_list" | awk -F', ' '{print NF}')
    ssd_active=2
    ssd_idle=1
    hdd_active=5
    hdd_idle=3
    ssd_wh=$(echo "scale=2; $ssd_count * (($ssd_active * $active_hours) + ($ssd_idle * $idle_hours))" | bc)
    hdd_wh=$(echo "scale=2; $hdd_count * (($hdd_active * $active_hours) + ($hdd_idle * $idle_hours))" | bc)
    total_wh=$(echo "scale=2; $ssd_wh + $hdd_wh" | bc)
    storage_kwh=$(echo "scale=3; $total_wh / 1000" | bc)
    echo "$storage_kwh"
}

# QUI: Vergeylen Anthony
# QUAND: 13/03/2025
# QUOI: Calcule la consommation quotidienne de l'écran en kWh, en considérant uniquement l'usage actif.
# Arguments: Aucun
# Sortie: Consommation de l'écran en kWh (string)
get_screen_consumption() {
    idle_power=0
    daily_wh=$(echo "scale=2; ($screen_active * $active_hours) + ($idle_power * $idle_hours)" | bc)
    screen_kwh=$(echo "scale=3; $daily_wh / 1000" | bc)
    echo "$screen_kwh"
}

# QUI: Vergeylen Anthony
# QUAND: 13/03/2025
# QUOI: Calcule la consommation quotidienne des autres composants (WiFi, Bluetooth, ventilateurs, etc.) en kWh.
# Arguments: Aucun
# Sortie: Consommation des autres composants en kWh (string)
get_other_consumption() {
    active_power=3
    idle_power=1
    daily_wh=$(echo "scale=2; ($active_power * $active_hours) + ($idle_power * $idle_hours)" | bc)
    others_kwh=$(echo "scale=3; $daily_wh / 1000" | bc)
    echo "$others_kwh"
}

cpu_kwh=$(get_cpu_consumption)
gpu_kwh=$(get_gpu_consumption)
mb_kwh=$(get_motherboard_consumption)
ram_kwh=$(get_ram_consumption)
storage_kwh=$(get_storage_consumption)
screen_kwh=$(get_screen_consumption)
others_kwh=$(get_other_consumption)

subtotal_kwh=$(echo "scale=3; $cpu_kwh + $gpu_kwh + $mb_kwh + $ram_kwh + $storage_kwh + $screen_kwh + $others_kwh" | bc)
psu_loss_kwh=$(echo "scale=3; $subtotal_kwh * (1 / $psu_efficiency - 1)" | bc)
total_kwh=$(echo "scale=3; $subtotal_kwh + $psu_loss_kwh" | bc)
kwh_per_month=$(echo "scale=3; $total_kwh * 30" | bc)
kwh_per_year=$(echo "scale=3; $total_kwh * 365" | bc)
avg_watt=$(echo "scale=3; ($total_kwh * 1000) / 24" | bc)

echo "============================================================"
echo "    ESTIMATION DE CONSOMMATION ÉNERGÉTIQUE - $system_type"
echo "============================================================"
echo "Heures actives : $active_hours h | Heures en veille : $idle_hours h"
echo "------------------------------------------------------------"
echo "Consommation CPU          : $cpu_kwh kWh/jour"
echo "Consommation GPU          : $gpu_kwh kWh/jour"
echo "Consommation Carte Mère   : $mb_kwh kWh/jour"
echo "Consommation RAM          : $ram_kwh kWh/jour"
echo "Consommation Stockage     : $storage_kwh kWh/jour"
echo "Consommation Écran        : $screen_kwh kWh/jour"
echo "Consommation Autres        : $others_kwh kWh/jour"
echo "------------------------------------------------------------"
echo "Subtotal (sans pertes PSU): $subtotal_kwh kWh/jour"
echo "Pertes alimentation (~$(echo "$psu_efficiency*100" | bc)%): $psu_loss_kwh kWh/jour"
echo "------------------------------------------------------------"
echo "Consommation Totale Estimée: $total_kwh kWh/jour (~$kwh_per_month kWh/mois ou ~$kwh_per_year kWh/an)"
echo "Puissance Moyenne         : $avg_watt W"
echo "============================================================"
echo "NOTE: Ces estimations sont approximatives et basées sur des valeurs moyennes."
echo ""

# Affichage des détails matériels détectés
echo "------------------ Détails matériels ------------------"
cpu_info=$(lscpu | grep "Model name:" | sed 's/Model name:\s*//')
[ -n "$cpu_info" ] && echo "Processeur         : $cpu_info"

gpu_info=$(lspci | grep -i "VGA\|3D" | head -n1)
[ -n "$gpu_info" ] && echo "Carte graphique    : $gpu_info"

ram_total=$(free -h | awk '/Mem:/ {print $2}')
[ -n "$ram_total" ] && echo "RAM                : $ram_total"

ssd_list=$(lsblk -d -o NAME,ROTA | awk '$2=="0" {print $1}' | paste -sd ', ' -)
if [ -n "$ssd_list" ]; then
    ssd_count=$(echo "$ssd_list" | awk -F', ' '{print NF}')
    echo "Disques SSD        : $ssd_count ($ssd_list)"
fi
hdd_list=$(lsblk -d -o NAME,ROTA | awk '$2=="1" {print $1}' | paste -sd ', ' -)
if [ -n "$hdd_list" ]; then
    hdd_count=$(echo "$hdd_list" | awk -F', ' '{print NF}')
    echo "Disques HDD        : $hdd_count ($hdd_list)"
fi

usb_list=$(lsusb)
if [ -n "$usb_list" ]; then
    usb_count=$(echo "$usb_list" | wc -l)
    echo "Périphériques USB  : $usb_count"
fi
echo "------------------------------------------------------------"
