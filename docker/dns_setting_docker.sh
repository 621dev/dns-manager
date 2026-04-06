#!/bin/bash
# ============================================================
# 도커 환경용 dns_setting.sh
# 주요 변경사항:
#   - rndc reload → rndc reload (named가 실행 중일 때만) 또는 kill -HUP
#   - ssh 기반 슬레이브 동기화는 동일하게 유지
#   - SCRIPT_DIR 기반 data/ 경로 사용
# ============================================================

set_dns() {
    while :
    do
        echo "==============================================="
        echo "1. slave 서버 등록"
        echo "2. 현재 서버를 slave 서버로 전환"
        echo "3. named.conf 수정"
        echo "q. 이전 메뉴 복귀"
        echo "==============================================="
        read -p "원하는 작업을 선택하세요: " _input
        case $_input in
            1) register_slave ;;
            2) change_slave ;;
            3)
                while :
                do
                    echo "============================================"
                    echo "named.conf 설정 수정"
                    echo "1. listen-on      (IPv4 리슨 주소)"
                    echo "2. allow query 수정"
                    echo "q. 이전 메뉴 복귀"
                    echo "============================================"
                    read -p "원하는 작업을 선택하세요 : " _input
                    if [ "$_input" == "q" ]; then break; fi
                    update_named_conf "$_input"
                done
                ;;
            q) return 0 ;;
            *) echo "잘못된 입력입니다. 다시 시도해주세요." ;;
        esac
    done
}

update_named_conf() {
    local _input=$1
    local _backuppath="$SCRIPT_DIR/data/dns_backup_$(date +%Y%m%d)"
    mkdir -p "$_backuppath"
    cp "/etc/named.conf" "$_backuppath/named.conf_$(date +%Y%m%d_%H%M).bak"

    case $_input in
        1)
            read -p "listen-on 값 입력 (예: any | 127.0.0.1) : " _listenonip
            sed -i "s/listen-on port 53 { .* };/listen-on port 53 { ${_listenonip}; };/" "/etc/named.conf"
            ;;
        2)
            read -p "allow-query 값 입력 : " _allowquery
            sed -i "s/allow-query { .* };/allow-query { ${_allowquery}; };/" "/etc/named.conf"
            ;;
        *) echo "잘못된 입력입니다. 다시 시도해주세요." ;;
    esac
}

change_slave() {
    local _masterip
    while :
    do
        read -p "마스터 서버의 IP 주소를 입력해주세요 (q. 이전 메뉴 복귀) : " _masterip
        if [ "$_masterip" == "q" ]; then return 0; fi
        if check_ip "$_masterip"; then break; fi
    done

    local _remotepath
    while :
    do
        read -p "마스터 서버의 named.rfc1912.zones 파일 경로 (기본값: /etc/named.rfc1912.zones, q. 복귀) : " _remotepath
        if [ "$_remotepath" == "q" ]; then return 0; fi
        if [ ! -n "$_remotepath" ]; then _remotepath="/etc/named.rfc1912.zones"; fi

        echo "마스터 서버(${_masterip})에서 파일을 가져오는 중..."
        if ssh "root@${_masterip}" "cat ${_remotepath}" > "/etc/named.rfc1912.zones" 2>> "$LOG_FILE"; then
            echo "파일 수신 완료"
            break
        else
            echo "파일 수신 실패. 경로를 다시 확인해주세요."
        fi
    done

    sed -i "s/listen-on port 53 { .* };/listen-on port 53 { ${DNS_IP}; };/" "/etc/named.conf"

    local _backuppath="$SCRIPT_DIR/data/dns_backup_$(date +%Y%m%d)"
    mkdir -p "$_backuppath/rfc1912.zones/" &>> "$LOG_FILE"
    cp "/etc/named.rfc1912.zones" "$_backuppath/rfc1912.zones/rfc1912.zones_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"

    sed -i "s/^MASTER_IP:.*/MASTER_IP:${_masterip}/" "${SCRIPT_DIR}/data/dns_data.txt"
    sed -i "s/^TYPE:.*/TYPE:slave/" "${SCRIPT_DIR}/data/dns_data.txt"

    local -a _zonearr
    zone_list_reload _zonearr
    for _zone in "${_zonearr[@]}"; do
        delete_zone_declaration "$_zone"
        if [[ "$_zone" == *in-addr.arpa ]]; then
            local _network=${_zone//.in-addr.arpa/}
            create_zone_declaration "$_zone" "${_network}.rev"
        else
            create_zone_declaration "$_zone" "${_zone}.zone"
        fi
    done

    _named_reload
}

register_slave() {
    local _slaveip
    while :
    do
        read -p "슬레이브 서버의 IP 주소를 입력해주세요 (q. 이전 메뉴 복귀) : " _slaveip
        if [ "$_slaveip" == "q" ]; then return 0; fi
        if check_ip "$_slaveip"; then break; fi
    done

    sed -i "s/listen-on port 53 { .* };/listen-on port 53 { ${DNS_IP}; };/" "/etc/named.conf"

    local _backuppath="$SCRIPT_DIR/data/dns_backup_$(date +%Y%m%d)"
    mkdir -p "$_backuppath/rfc1912.zones/" &>> "$LOG_FILE"
    cp "/etc/named.rfc1912.zones" "$_backuppath/rfc1912.zones/rfc1912.zones_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"

    sed -i "s/^SLAVE_IP:.*/SLAVE_IP:${_slaveip}/" "${SCRIPT_DIR}/data/dns_data.txt"
    sed -i "s/^TYPE:.*/TYPE:master/" "${SCRIPT_DIR}/data/dns_data.txt"

    local -a _zonearr
    zone_list_reload _zonearr
    for _zone in "${_zonearr[@]}"; do
        delete_zone_declaration "$_zone"
        if [[ "$_zone" == *in-addr.arpa ]]; then
            local _network=${_zone//.in-addr.arpa/}
            create_zone_declaration "$_zone" "${_network}.rev"
        else
            create_zone_declaration "$_zone" "${_zone}.zone"
        fi
    done
    echo "${_slaveip} 등록이 완료되었습니다."
    _named_reload
}

update_hostname() {
    read -p "새로운 hostname을 입력해주세요 : " _hostname
    hostname "$_hostname"
    echo "hostname이 \"$_hostname\"(으)로 변경되었습니다."
}

reload_dns_decl() {
    local -a _masterzonearr=()
    local -a _slavezonearr=()
    local _remotepath="/etc/named.rfc1912.zones"
    local _masterip=$(awk -F':' '/MASTER_IP/ {print $2}' "${SCRIPT_DIR}/data/dns_data.txt")
    local _backuppath="$SCRIPT_DIR/data/dns_backup_$(date +%Y%m%d)/zonefile"
    mkdir -p "$_backuppath" &>> "$LOG_FILE"
    zone_list_reload _slavezonearr

    echo "마스터 서버(${_masterip})에서 파일을 가져오는 중..."
    if ssh "root@${_masterip}" "cat ${_remotepath}" > "${SCRIPT_DIR}/data/named.rfc1912.zones" 2>> "$LOG_FILE"; then
        echo "파일 수신 완료"
        zone_list_reload _masterzonearr "${SCRIPT_DIR}/data/named.rfc1912.zones"
        local _add_zones=()
        local _del_zones=()

        for _zone in "${_masterzonearr[@]}"; do
            if [[ ! " ${_slavezonearr[*]} " =~ " ${_zone} " ]]; then
                _add_zones+=("$_zone")
            fi
        done

        for _zone in "${_slavezonearr[@]}"; do
            if [[ ! " ${_masterzonearr[*]} " =~ " ${_zone} " ]]; then
                _del_zones+=("$_zone")
            fi
        done

        echo "추가 대상: ${_add_zones[*]:-none}"
        echo "삭제 대상: ${_del_zones[*]:-none}"
        sleep 2

        for _zone in "${_add_zones[@]}"; do
            echo "$_zone 선언을 추가합니다."
            if [[ "$_zone" == *in-addr.arpa ]]; then
                local _network=${_zone//.in-addr.arpa/}
                create_zone_declaration "$_zone" "${_network}.rev"
            else
                create_zone_declaration "$_zone" "${_zone}.zone"
            fi
        done

        for _zone in "${_del_zones[@]}"; do
            echo "$_zone 선언을 삭제합니다."
            delete_zone_declaration "$_zone"
            if [[ "$_zone" == *in-addr.arpa ]]; then
                local _network=${_zone//.in-addr.arpa/}
                local _revfile="/var/named/${_network}.rev"
                cp "$_revfile" "$_backuppath/${_network}.rev_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
                rm -f "$_revfile"
            else
                cp "/var/named/${_zone}.zone" "$_backuppath/${_zone}.zone_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
                rm -f "/var/named/${_zone}.zone"
            fi
        done

        _named_reload
    else
        echo "파일 수신 실패. 경로를 다시 확인해주세요."
    fi
}

# named 재로드 헬퍼 (rndc 또는 SIGHUP 폴백)
_named_reload() {
    if pgrep -x named > /dev/null 2>&1; then
        if rndc reload &>> "$LOG_FILE"; then
            echo "named 설정이 재로드되었습니다."
        else
            kill -HUP $(pgrep -x named)
            echo "named 설정이 SIGHUP으로 재로드되었습니다."
        fi
    else
        echo "named가 실행 중이지 않습니다. 재로드를 건너뜁니다."
    fi
}
