#!/bin/bash
# ============================================================
# set_dns()          : DNS 설정 메뉴 (slave 등록 / slave 전환 / named.conf 수정)
# update_named_conf(): named.conf의 listen-on, listen-on-v6 값 수정
# change_slave()     : 현재 서버를 slave로 전환 (마스터 IP 입력, rfc1912.zones 동기화)
# register_slave()   : slave 서버 등록 (slave IP 입력, zone 선언 재생성)
# update_hostname()  : 서버 hostname 변경
# reload_dns_decl()  : 마스터에서 rfc1912.zones를 가져와 slave zone 선언 갱신
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
            1)
                register_slave
                ;;
            2)
                change_slave
                ;;
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
            q)
                return 0
                ;;
            *)
                echo "잘못된 입력입니다. 다시 시도해주세요."
                ;;
        esac
    done
}

# TODO: 메뉴 ip v6 제외
update_named_conf() {
    local _input=$1
    local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)"
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
        *)  
            echo "잘못된 입력입니다. 다시 시도해주세요."
            ;;
    esac       
}

change_slave() {
    # named.conf 설정 변경
    # update_hostname

    local _masterip
    while : 
    do
        read -p "마스터 서버의 IP 주소를 입력해주세요 (q. 이전 메뉴 복귀) : " _masterip
        if [ "$_masterip" == "q" ]; then return 0; fi
        if check_ip "$_masterip"; then break; fi
    done

    # TODO : 마스터 서버의 타입이 none이면 전환 취소
    
    # 마스터 서버로부터 named.rfc1912.zones 파일 가져오기
    local _remotepath
    while :
    do
        read -p "마스터 서버의 named.rfc1912.zones 파일 경로를 입력해주세요 (기본값: /etc/named.rfc1912.zones, q. 이전 메뉴 복귀) : " _remotepath
        if [ "$_remotepath" == "q" ]; then return 0; fi
        if [ ! -n "$_remotepath" ]; then _remotepath="/etc/named.rfc1912.zones"; fi

        echo "마스터 서버(${_masterip})에서 파일을 가져오는 중..."
        if ssh "root@${_masterip}" "cat ${_remotepath}" > "/etc/named.rfc1912.zones" 2>> "$LOG_FILE"; then
            echo "파일 수신 완료: ${_masterip}:${_remotepath} → /etc/named.rfc1912.zones"
            break
        else
            echo "파일 수신 실패. 경로를 다시 확인해주세요."
        fi
    done

    sed -i "s/listen-on port 53 { .* };/listen-on port 53 { ${DNS_IP}; };/" "/etc/named.conf"

    # 백업
    local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)"
    mkdir -p "$_backuppath/rfc1912.zones/" &>> "$LOG_FILE"
    cp "/etc/named.rfc1912.zones" "$_backuppath/rfc1912.zones/rfc1912.zones_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"

    # dns_data.txt 파일 수정
    sed -i "s/^MASTER_IP:.*/MASTER_IP:${_masterip}/" "${SCRIPT_DIR}/dns_data.txt"
    sed -i "s/^TYPE:.*/TYPE:slave/" "${SCRIPT_DIR}/dns_data.txt"
    
    # 가져온 named.rfc1912.zones 파일에 자동으로 추가
    local -a _zonearr
    zone_list_reload _zonearr
    for _zone in "${_zonearr[@]}"; do
        delete_zone_declaration "$_zone"
        if [[ "$_zone" == *in-addr.arpa ]]; then # 역방향
            local _network=${_zone//.in-addr.arpa/}
            create_zone_declaration "$_zone" "${_network}.rev"
        else
            create_zone_declaration "$_zone" "${_zone}.zone"
        fi        
    done

    rndc reload
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

    # 백업
    local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)"
    mkdir -p "$_backuppath/rfc1912.zones/" &>> "$LOG_FILE"
    cp "/etc/named.rfc1912.zones" "$_backuppath/rfc1912.zones/rfc1912.zones_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"

    # dns_data.txt 파일 수정
    sed -i "s/^SLAVE_IP:.*/SLAVE_IP:${_slaveip}/" "${SCRIPT_DIR}/dns_data.txt"
    sed -i "s/^TYPE:.*/TYPE:master/" "${SCRIPT_DIR}/dns_data.txt"
    
    # zone 선언 삭제 후 재생성
    local -a _zonearr
    zone_list_reload _zonearr
    for _zone in "${_zonearr[@]}"; do
        delete_zone_declaration "$_zone"
        if [[ "$_zone" == *in-addr.arpa ]]; then # 역방향
            local _network=${_zone//.in-addr.arpa/} 
            create_zone_declaration "$_zone" "${_network}.rev"
        else    # 정방향
            create_zone_declaration "$_zone" "${_zone}.zone"
        fi
    done
    echo "${_slaveip} 등록이 완료되었습니다."
    rndc reload
}


# hostname 변경
update_hostname() {
    read -p "새로운 hostname을 입력해주세요 : " _hostname
    hostnamectl set-hostname "$_hostname"
    echo "hostname이 \"$_hostname\"(으)로 변경되었습니다."
}

# named.rfc1219.named 파일을 갱신
reload_dns_decl() {
    local -a _masterzonearr=()
    local -a _slavezonearr=()
    local _remotepath="/etc/named.rfc1912.zones"
    local _masterip=$(awk -F':' '/MASTER_IP/ {print $2}' "${SCRIPT_DIR}/dns_data.txt")
    local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)/zonefile"
    mkdir -p "$_backuppath" &>> "$LOG_FILE"
    zone_list_reload _slavezonearr

    echo "마스터 서버(${_masterip})에서 파일을 가져오는 중..."
    if ssh "root@${_masterip}" "cat ${_remotepath}" > "${SCRIPT_DIR}/named.rfc1912.zones" 2>> "$LOG_FILE"; then
        echo "파일 수신 완료: ${_masterip}:${_remotepath} → ${SCRIPT_DIR}/named.rfc1912.zones"
        zone_list_reload _masterzonearr "${SCRIPT_DIR}/named.rfc1912.zones"
        local _add_zones=()
        local _del_zones=()
        # 분류
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
        echo "==============================================="
        echo "추가 대상: ${_add_zones[*]:-none}"
        echo "삭제 대상: ${_del_zones[*]:-none}"
        echo "==============================================="
        sleep 2
        # 마스터에만 있는 존 선언을 슬레이브에 추가
        for _zone in "${_add_zones[@]}"
        do
            echo "$_zone 선언을 추가합니다." 
            if [[ "$_zone" == *in-addr.arpa ]]; then # 역방향
                local _network=${_zone//.in-addr.arpa/}
                create_zone_declaration "$_zone" "${_network}.rev"
            else    # 정방향
                create_zone_declaration "$_zone" "${_zone}.zone"
            fi
        done

        # 슬레이브에만 있는 존 선언을 삭제 (존파일도 같이 삭제)
        for _zone in "${_del_zones[@]}"
        do
            echo "$_zone 선언을 삭제합니다." 
            delete_zone_declaration "$_zone"
            if [[ "$_zone" == *in-addr.arpa ]]; then # 역방향
                local _network=${_zone//.in-addr.arpa/}
                local _revfile="/var/named/${_network}.rev"
                # zone 파일 백업 후 삭제 (network_delete_zone에서 가져옴 추후 통합)
                cp "$_revfile" "$_backuppath/${_network}.rev_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
                echo "${_network}.rev 파일이 백업되었습니다. (백업 위치 : $_backuppath/zonefile/)"
                rm -f "$_revfile"
                echo "${_network}.in-addr.arpa 역방향 네트워크가 삭제되었습니다."
            else    # 정방향
                # zone 파일을 백업 후 삭제 (domain_delete_zone에서 가져옴 추후 통합)
                cp "/var/named/${_zone}.zone" "$_backuppath/${_zone}.zone_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
                echo "${_zone}.zone 파일이 백업되었습니다. (백업 위치 : $_backuppath/${_zone}.zone_$(date +%Y%m%d_%H%M).bak)"
                rm -f "/var/named/${_zone}.zone"
                echo "${_zone} 도메인이 삭제되었습니다."
            fi    
        done

        rndc reload
    else
        echo "파일 수신 실패. 경로를 다시 확인해주세요."
    fi
}