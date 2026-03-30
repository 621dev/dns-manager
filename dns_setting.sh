#!/bin/bash
# DNS 세팅 메뉴

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
                    echo "2. listen-on-v6   (IPv6 리슨 주소)"
                    echo "q. 이전 메뉴 복귀"
                    echo "============================================"
                    read -p "원하는 작업을 선택하세요 : " _input
                    if [ "$_input" == "q" ]; then continue; fi
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
            read -p "listen-on-v6 값 입력 (예: none | [::1]) : " _listenonip
            sed -i "s/listen-on-v6 port 53 { .* };/listen-on-v6 port 53 { ${_listenonip}; };/" "/etc/named.conf" 
            ;;
        3)
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
    mkdir -p "$backuppath/rfc1912.zones/" &>> "$LOG_FILE"
    cp "/etc/named.rfc1912.zones" "$backuppath/rfc1912.zones/rfc1912.zones_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"

    # slave zone 선언 추가
    # 직접 입력
    
    # 가져온 named.rfc1912.zones 파일에 자동으로 추가
    local -a _zonearr
    zone_list_reload _zonearr
    for _zone in "${_zonearr[@]}"; do
        delete_zone_declaration "$_zone"
        if [[ "$_zone" == *in-addr.arpa ]]; then # 역방향
            local _network=${_zone//.in-addr.arpa/}
            cat << EOF >> /etc/named.rfc1912.zones

zone "${_zone}" IN {
        type slave;
        file "slaves/${_network}.rev";
        masters { ${_masterip}; };
};
EOF
        else
            cat << EOF >> /etc/named.rfc1912.zones

zone "${_zone}" IN {
        type slave;
        file "slaves/${_zone}.zone";
        masters { ${_masterip}; };
};
EOF
        fi 
    done
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
    mkdir -p "$backuppath/rfc1912.zones/" &>> "$LOG_FILE"
    cp "/etc/named.rfc1912.zones" "$backuppath/rfc1912.zones/rfc1912.zones_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"

    #
    local -a _zonearr
    zone_list_reload _zonearr
    echo "debug : ${_zonearr[@]}"
    for _zone in "${_zonearr[@]}"; do
        delete_zone_declaration "$_zone"
        if [[ "$_zone" == *in-addr.arpa ]]; then # 역방향
            local _network=${_zone//.in-addr.arpa/} 
            cat << EOF >> /etc/named.rfc1912.zones

zone "${_zone}" IN {
        type master;
        file "${_network}.rev";
        allow-update { none; };
        allow-transfer { ${_slaveip}; };
        also-notify { ${_slaveip}; };
};
EOF
        else
            cat << EOF >> /etc/named.rfc1912.zones

zone "${_zone}" IN {
        type master;
        file "${_zone}.zone";
        allow-update { none; };
        allow-transfer { ${_slaveip}; };
        also-notify { ${_slaveip}; };
};
EOF
        fi
    done
    echo "${_slaveip} 등록이 완료되었습니다."
}


# hostname 변경
update_hostname() {
    read -p "새로운 hostname을 입력해주세요 : " _hostname
    hostnamectl set-hostname "$_hostname"
    echo "hostname이 \"$_hostname\"(으)로 변경되었습니다."
}