# Energy Consumption Estimation Script

This repository contains a Bash script that estimates the daily, monthly, and yearly energy consumption of your system based on hardware information and user-specified active hours. The script gathers system details using standard Linux utilities and applies usage coefficients to calculate estimated power usage in kilowatt-hours (kWh).

---

## Features

- **Dependency Check:**  
  The script verifies that all required commands (e.g., `lscpu`, `lsblk`, `dmidecode`, `lspci`, `bc`, `free`, `xrandr`, `lsusb`) are installed. If a dependency is missing, it prompts you with an installation command.

- **User Input for Active Hours:**  
  Prompts the user to enter the number of active hours per day (between 0 and 24). The remaining hours are considered idle.

- **System Type Detection:**  
  Uses `dmidecode` to detect the chassis type (e.g., Desktop, Tower, Gaming) and adjusts energy consumption multipliers accordingly.

- **Component-wise Energy Calculation:**  
  Estimates the daily energy consumption (in kWh) for:
  - **CPU:** Based on the TDP value and usage multipliers.
  - **GPU:** Detects the GPU type and applies corresponding coefficients.
  - **Motherboard/Chipset:** Uses fixed active/idle consumption values.
  - **RAM:** Calculates consumption from total memory and predefined active/idle rates.
  - **Storage Devices (SSD/HDD):** Determines consumption from the number of devices and their active/idle power ratings.
  - **Screen:** Considers active power usage.
  - **Other Components:** Includes peripherals like WiFi, Bluetooth, and fans.

- **Power Supply Losses:**  
  Takes into account PSU efficiency (default 87%) to estimate additional losses, providing a more realistic total consumption figure.

- **Detailed Summary:**  
  Displays:
  - Consumption per component (CPU, GPU, motherboard, RAM, storage, screen, others).
  - Subtotal consumption (without PSU losses) and the estimated losses.
  - Total estimated consumption per day, as well as extrapolated values for monthly and yearly usage.
  - Average power in Watts computed from the total daily consumption.

- **Hardware Details:**  
  Outputs key hardware information such as the CPU model, GPU details, total RAM, SSD/HDD count, and connected USB devices.

---

## Usage

1. **Copy the Script:**  
   Save the script (e.g., as `energy_estimation.sh`) to a location on your system.

2. **Make it Executable:**
   ```bash
   chmod +x energy_estimation.sh
3. **Run the Script:**
`sudo ./energy_estimation.sh`

Note: Running as sudo may be necessary since some commands (like dmidecode) require root privileges.

Requirements  
Operating System: Linux  
Dependencies:  
Ensure the following commands are installed:  
- lscpu  
- lsblk  
- dmidecode  
- lspci  
- bc  
- free  
- xrandr  
- lsusb  

The script will notify you if any are missing and suggest installation commands.

Disclaimer  
The energy consumption estimations provided by this script are approximate. They are based on average hardware values and assumed usage patterns. Actual power consumption may vary depending on your system’s configuration and real-world usage.
