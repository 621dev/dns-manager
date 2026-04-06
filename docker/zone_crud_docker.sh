#!/bin/bash
# ============================================================
# 도커 환경용 zone_crud.sh
# 주요 변경사항:
#   - rndc reload → _named_reload() 헬퍼 사용 (프로세스 기반)
#   - SCRIPT_DIR/data/dns_data.txt 경로 사용
#   - SCRIPT_DIR/data/dns_backup_* 백업 경로 사용
# ============================================================

add_forward_zone() {
    local _inputdomain
    local _inputip
    local _serial=$(date +%Y%m%d)01

    while :
    do
        echo "============================================"
        echo "기준 도메인 입력 (예 : naver.com, q. 복귀)"
        echo "============================================"
        read -p "도메인 : " _inputdomain
        if [ "$_inputdomain" == "q" ]; then return 0; fi

        if grep -E "^zone[[:space:]]+\"${_inputdomain}\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
            delete_zone_declaration "$_inputdomain"
            continue
        fi

        if [ -f "/var/named/${_inputdomain}.zone" ]; then
            echo "${_inputdomain}.zone 파일이 이미 존재합니다. 백업 후 새로 생성합니다."
            local _backuppath="$SCRIPT_DIR/data/dns_backup_$(date +%Y%m%d)/zonefile"
            mkdir -p "$_backuppath" &>> "$LOG_FILE"
            cp "/var/named/${_inputdomain}.zone" "$_backuppath/${_inputdomain}.zone_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
            rm -rf "/var/named/${_inputdomain}.zone"
        fi

        while :
        do
            read -p "IP를 입력해주세요 (0. 이전 메뉴 복귀) : " _inputip
            if [ "$_inputip" == "0" ]; then return 0
            elif ! check_ip "$_inputip"; then continue
            fi
            break
        done

        echo "도메인 ${_inputdomain}을 추가합니다."
        create_zone_declaration "${_inputdomain}" "${_inputdomain}.zone"

        cat << EOF > /var/named/${_inputdomain}.zone
\$TTL 3H
@       IN SOA  ns1.${_inputdomain}. adminemail. (
                                        ${_serial}   ; serial
                                        1D          ; refresh
                                        1H          ; retry
                                        1W          ; expire
                                        3H          ; minimum
                                        )
        IN NS   ns1.${_inputdomain}.

ns1     IN A    ${DNS_IP}
@       IN A    ${_inputip}

EOF
        chown root:named /var/named/${_inputdomain}.zone
        chmod 640 /var/named/${_inputdomain}.zone
        echo "${_inputdomain}.zone 파일 생성 완료."
        _named_reload
    done
}

add_reverse_zone() {
    local _inputip
    local -a _iparr=()
    local _inputdomain
    local _serial=$(date +%Y%m%d)01
    local _hostoctet
    while :
    do
        _inputip=""
        _iparr=()
        _inputdomain=""
        _hostoctet=""

        echo "============================================"
        echo "기준 IP 입력 (예 : 192.168.10.1, q. 복귀)"
        echo "============================================"
        read -p "IP : " _inputip
        if [ "$_inputip" == "q" ]; then return 0
        elif ! check_ip "$_inputip"; then continue; fi
        _iparr=( $(split_dot "$_inputip") )
        _hostoctet=${_iparr[3]}
        local _reverseip="${_iparr[2]}.${_iparr[1]}.${_iparr[0]}"

        if grep -E "^zone[[:space:]]+\"${_reverseip}\.in-addr\.arpa\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
            echo "${_reverseip} 대역대는 이미 선언되었습니다. Zone 수정에서 host를 추가해주세요."
            return 1
        fi

        create_zone_declaration "${_reverseip}.in-addr.arpa" "${_reverseip}.rev"

        while :
        do
            read -p "기준 도메인 입력 (q. 복귀) : " _inputdomain
            if [ "$_inputdomain" == "q" ]; then return 0; fi
            break
        done

        if [ -f "/var/named/${_reverseip}.rev" ]; then
            if grep -E "^${_hostoctet}[[:space:]]+IN[[:space:]]+PTR" "/var/named/${_reverseip}.rev" &>> "$LOG_FILE"; then
                echo "이미 ${_hostoctet}이 중복되어 있습니다."
                continue
            fi
            cat << EOF >> "/var/named/${_reverseip}.rev"
${_hostoctet}    IN PTR  ns1.${_inputdomain}.
EOF
        else
            cat << EOF > "/var/named/${_reverseip}.rev"
\$TTL 3H
@       IN SOA  ns1.${_inputdomain}. adminemail. (
                                        ${_serial}  ; serial
                                        1D          ; refresh
                                        1H          ; retry
                                        1W          ; expire
                                        3H          ; minimum
                                        )
        IN NS   ns1.${_inputdomain}.

; PTR 레코드
EOF
            printf "%-7s IN PTR    %s\n" "$_hostoctet" "ns1.$_inputdomain." >> "/var/named/${_reverseip}.rev"
            chown root:named /var/named/${_reverseip}.rev
            chmod 640 /var/named/${_reverseip}.rev
        fi
        echo "${_inputip} 역방향 zone 생성 완료."
        _named_reload
    done
}

domain_delete_zone() {
    local _inputdomain=$1
    local _backuppath="$SCRIPT_DIR/data/dns_backup_$(date +%Y%m%d)/zonefile"

    if ! grep -E "^zone[[:space:]]+\"${_inputdomain}\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
        echo "${_inputdomain}은 named.rfc1912.zones에 선언되지 않았습니다."
        return 1
    fi

    if [ ! -f "/var/named/${_inputdomain}.zone" ]; then
        echo "${_inputdomain}.zone 파일이 존재하지 않습니다."
        return 1
    fi

    delete_zone_declaration "$_inputdomain"

    mkdir -p "$_backuppath" &>> "$LOG_FILE"
    cp "/var/named/${_inputdomain}.zone" "$_backuppath/${_inputdomain}.zone_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    rm -rf "/var/named/${_inputdomain}.zone"
    echo "${_inputdomain} 도메인이 삭제되었습니다."
    _named_reload
}

network_delete_zone() {
    local _inputip="${1}.255"
    if ! check_ip "$_inputip"; then return 1; fi
    local -a _iparr
    _iparr=( $(split_dot "$_inputip") )
    local _reverseip="${_iparr[2]}.${_iparr[1]}.${_iparr[0]}"
    local _revfile="/var/named/${_reverseip}.rev"
    local _backuppath="$SCRIPT_DIR/data/dns_backup_$(date +%Y%m%d)"

    if ! grep -E "^zone[[:space:]]+\"${_reverseip}\.in-addr\.arpa\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
        echo "${_reverseip}.in-addr.arpa 는 named.rfc1912.zones에 선언되지 않았습니다."
        return 1
    fi

    delete_zone_declaration "${_reverseip}.in-addr.arpa"

    if [ ! -f "$_revfile" ]; then
        echo "${_reverseip}.rev 파일이 존재하지 않습니다."
        return 1
    fi

    mkdir -p "$_backuppath/zonefile" &>> "$LOG_FILE"
    cp "$_revfile" "$_backuppath/zonefile/${_reverseip}.rev_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    rm -f "$_revfile"
    echo "${_reverseip}.in-addr.arpa 역방향 네트워크가 삭제되었습니다."
    _named_reload
}

hostip_delete_zone() {
    local _inputnetwork=$1
    local -a _iparr
    _iparr=( $(split_dot "$_inputnetwork") )
    local _reverseip="${_iparr[2]}.${_iparr[1]}.${_iparr[0]}"
    local _revfile="/var/named/${_reverseip}.rev"
    local _backuppath="$SCRIPT_DIR/data/dns_backup_$(date +%Y%m%d)"

    if ! grep -E "^zone[[:space:]]+\"${_reverseip}\.in-addr\.arpa\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
        echo "${_reverseip}.in-addr.arpa는 named.rfc1912.zones에 선언되지 않았습니다."
        return 1
    fi

    while :
    do
        read -p "삭제할 호스트 IP 마지막 옥텟 (q. 복귀) : " _inputhost
        if [ "$_inputhost" == "q" ]; then return 0
        elif ! check_ip "${_inputnetwork}.${_inputhost}"; then continue
        fi

        mkdir -p "$_backuppath/zonefile" &>> "$LOG_FILE"
        cp "$_revfile" "$_backuppath/zonefile/${_reverseip}.rev_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
        update_serial "$_revfile"
        sed -Ei "/^${_inputhost}[[:space:]]+IN[[:space:]]+PTR/d" "$_revfile"
        echo "${_inputnetwork}.${_inputhost} 호스트가 삭제되었습니다."
        _named_reload
    done
}

create_zone_declaration() {
    local _zone=$1
    local _zonefile=$2
    local _type=$(get_dns_type)
    local _masterip=$(awk -F':' '/MASTER_IP/ {print $2}' "${SCRIPT_DIR}/data/dns_data.txt")
    local _slaveip=$(awk -F':' '/SLAVE_IP/ {print $2}' "${SCRIPT_DIR}/data/dns_data.txt")

    if [[ "$_type" == "master" ]]; then
        cat << EOF >> /etc/named.rfc1912.zones

zone "${_zone}" IN {
        type master;
        file "${_zonefile}";
        allow-update { none; };
        allow-transfer { ${_slaveip}; };
        also-notify { ${_slaveip}; };
};
EOF
    elif [[ "$_type" == "none" ]]; then
        cat << EOF >> /etc/named.rfc1912.zones

zone "${_zone}" IN {
        type master;
        file "${_zonefile}";
        allow-update {none;};
        allow-transfer { none; };
        also-notify { };
};
EOF
    elif [[ "$_type" == "slave" ]]; then
        cat << EOF >> /etc/named.rfc1912.zones

zone "${_zone}" IN {
        type slave;
        file "slaves/${_zonefile}";
        masters { ${_masterip}; };
};
EOF
    fi

    update_decl_serial "${SCRIPT_DIR}/data/dns_data.txt"
}

delete_zone_declaration() {
    local _target=$1
    local _startline=0
    local _endline=0

    _startline=$(grep -En "^zone[[:space:]]+\"$_target\"[[:space:]]+IN" /etc/named.rfc1912.zones | cut -d: -f1)
    if [ ! -n "$_startline" ]; then return 1; fi

    _endline=$(tail -n +$((_startline + 1)) /etc/named.rfc1912.zones | grep -En "^zone[[:space:]]+\"" | head -1 | cut -d: -f1)

    if [ -n "$_endline" ]; then
        _endline=$((_startline + _endline - 1))
    else
        _endline=$(wc -l /etc/named.rfc1912.zones | awk '{print $1}')
    fi

    local _backuppath="$SCRIPT_DIR/data/dns_backup_$(date +%Y%m%d)"
    mkdir -p "$_backuppath/rfc1912.zones/" &>> "$LOG_FILE"
    cp "/etc/named.rfc1912.zones" "$_backuppath/rfc1912.zones/rfc1912.zones_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"

    sed -i "${_startline},${_endline}d" /etc/named.rfc1912.zones
    echo "${_target} 존 선언이 삭제되었습니다."
    update_decl_serial "${SCRIPT_DIR}/data/dns_data.txt"
}

add_forward_service() {
    local _domain=$1
    local _service=$2
    local _ip=$3
    local _zonefile="/var/named/${_domain}.zone"
    local _backuppath="$SCRIPT_DIR/data/dns_backup_$(date +%Y%m%d)/zonefile"

    if ! check_ip "$_ip"; then return 1; fi

    if grep -E "^${_service}[[:space:]]+IN[[:space:]]+A" "$_zonefile" &>> "$LOG_FILE"; then
        echo "${_service} 서비스가 이미 등록되었습니다."
        return 1
    fi

    mkdir -p "$_backuppath" &>> "$LOG_FILE"
    cp "$_zonefile" "$_backuppath/${_domain}.zone_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    update_serial "$_zonefile"
    printf "%-7s IN A    %s\n" "$_service" "$_ip" >> "$_zonefile"
    echo "${_service} 서비스가 추가되었습니다."
    _named_reload
}

delete_forward_service() {
    local _domain=$1
    local _service=$2
    local _zonefile="/var/named/${_domain}.zone"
    local _backuppath="$SCRIPT_DIR/data/dns_backup_$(date +%Y%m%d)/zonefile"

    if ! grep -E "^${_service}[[:space:]]+IN[[:space:]]+A" "$_zonefile" &>> "$LOG_FILE"; then
        echo "${_service} 서비스가 등록되지 않았습니다."
        return 1
    fi

    mkdir -p "$_backuppath" &>> "$LOG_FILE"
    cp "$_zonefile" "$_backuppath/${_domain}.zone_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    update_serial "$_zonefile"
    sed -Ei "/^${_service}[[:space:]]+IN[[:space:]]+A/d" "$_zonefile"
    echo "${_service} 서비스가 삭제되었습니다."
    _named_reload
}

add_reverse_host() {
    local _domain=$1
    local _network=$2
    local _hostip=$3
    local _revfile="/var/named/${_network}.rev"
    local _backuppath="$SCRIPT_DIR/data/dns_backup_$(date +%Y%m%d)/zonefile"

    if ! check_ip "$_network.$_hostip"; then return 1; fi

    if grep -E "^${_hostip}[[:space:]]+IN[[:space:]]+PTR" "$_revfile" &>> "$LOG_FILE"; then
        echo "이미 ${_hostip}는 사용 중입니다."
        return 1
    fi

    mkdir -p "$_backuppath" &>> "$LOG_FILE"
    cp "$_revfile" "$_backuppath/${_network}.rev_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    update_serial "$_revfile"
    printf "%-7s IN PTR    %s\n" "$_hostip" "$_domain" >> "$_revfile"
    echo "${_hostip}가 추가되었습니다."
    _named_reload
}

delete_reverse_host() {
    local _network=$1
    local _hostip=$2
    local _revfile="/var/named/${_network}.rev"
    local _backuppath="$SCRIPT_DIR/data/dns_backup_$(date +%Y%m%d)/zonefile"

    if ! grep -E "^${_hostip}[[:space:]]+IN[[:space:]]+PTR" "$_revfile" &>> "$LOG_FILE"; then
        echo "${_hostip}는 등록되지 않았습니다."
        return 1
    elif ! check_ip "${_network}.${_hostip}"; then
        return 1
    fi

    mkdir -p "$_backuppath" &>> "$LOG_FILE"
    cp "$_revfile" "$_backuppath/${_network}.rev_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    update_serial "$_revfile"
    sed -Ei "/^${_hostip}[[:space:]]+IN[[:space:]]+PTR/d" "$_revfile"
    echo "${_hostip}가 삭제되었습니다."
    _named_reload
}
