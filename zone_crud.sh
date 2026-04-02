#!/bin/bash
# ============================================================
# add_forward_zone()        : 정방향 Zone 선언 및 zone 파일 생성
# add_reverse_zone()        : 역방향 Zone 선언 및 .rev 파일 생성/수정
# domain_delete_zone()      : 도메인 기준으로 정방향 Zone 삭제
# network_delete_zone()     : 네트워크 대역 기준으로 역방향 Zone 전체 삭제
# hostip_delete_zone()      : 역방향 Zone에서 특정 호스트 IP 레코드만 삭제
# create_zone_declaration() : rfc1912.zones에 zone 선언 블록 추가 (master/slave 자동 분기)
# delete_zone_declaration() : rfc1912.zones에서 zone 선언 블록 삭제
# add_forward_service()     : 정방향 Zone에 A 레코드 추가
# delete_forward_service()  : 정방향 Zone에서 A 레코드 삭제
# add_reverse_host()        : 역방향 Zone에 PTR 레코드 추가
# delete_reverse_host()     : 역방향 Zone에서 PTR 레코드 삭제
# ============================================================

# 정방향 도메인 추가
# 존을 추가할 때는 zone 선언이 안되어있는데 zone 파일이 있을 경우 zone 파일을 삭제하고 새로 생성한다.
add_forward_zone() {
    local _inputdomain    # 입력 받을 도메인
    local _inputip        # 입력 받을 ip
    local _servicearr=()  # 입력 받을 서비스의 배열
    local _serial=$(date +%Y%m%d)01  # zone파일 시리얼 넘버

    while :
    do
        echo "============================================"
        echo "기준 도메인을 입력해주세요"
        echo "(www와 같은 Host Name을 제외하고 입력해야합니다. 예 : naver.com)"
        echo "q.이전 메뉴 복귀"
        echo "============================================"
        read -p "도메인 : " _inputdomain
        if [ "$_inputdomain" == "q" ]; then return 0; fi

        # TODO: 도메인명 유효성 검사 추가 필요 (RFC 1123 형식, 특수문자 제한)

        # zone 선언 파일 검사 (/etc/named.rfc1912.zone)
        if grep -E "^zone[[:space:]]+\"${_inputdomain}\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
            # rfc1912.zones 파일에서 해당 도메인을 삭제
            delete_zone_declaration "$_inputdomain"
            continue
        fi

        # zone 파일 검사 (/var/named/)
        if [ -f "/var/named/${_inputdomain}.zone" ]; then
            echo "${_inputdomain}.zone 파일이 이미 존재합니다."
            echo "해당 zone 파일을 백업하고 새로 생성하겠습니다."
            local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)/zonefile"
            mkdir -p "$_backuppath" &>> "$LOG_FILE"
            cp "/var/named/${_inputdomain}.zone" "$_backuppath/${_inputdomain}.zone_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
            echo "${_inputdomain}.zone 파일이 백업되었습니다. (백업 위치 : $_backuppath/${_inputdomain}.zone_$(date +%Y%m%d_%H%M).bak)"
            rm -rf "/var/named/${_inputdomain}.zone"
        fi

        # ip 입력
        while :
        do
            read -p "IP를 입력해주세요 (이전 메뉴로 돌아가려면 0 입력) : " _inputip
            if [ "$_inputip" == "0" ]; then return 0
            elif ! check_ip "$_inputip"; then continue
            fi
            break
        done

        # # 서비스 입력
        # _servicearr=()
        # while :
        # do
        #     read -p "서비스를 입력해주세요 (www, mail, @ 등 / 다음 단계로 진행하려면 1 입력) : " _inputservice
        #     if [ "$_inputservice" == "1" ]; then break; fi
        #     _servicearr+=("$_inputservice")
        #     echo "현재 입력된 서비스 : ${_servicearr[@]}"
        # done

        # rfc1912.zones 파일에 선언 추가
        echo "도메인 ${_inputdomain}을 추가합니다."
        create_zone_declaration "${_inputdomain}" "${_inputdomain}.zone"
        # zone 파일 생성
        echo "${_inputdomain}의 Zone 파일을 생성합니다."
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
        # zone 파일에 서비스 추가
        for _service in "${_servicearr[@]}"; do
            printf "%-7s IN A    %s\n" "$_service" "$_inputip" >> /var/named/${_inputdomain}.zone
        done

        echo "${_inputdomain}.zone 파일이 생성을 완료하였습니다."

        # zone 파일 소유자 및 그룹 권한 설정
        echo "${_inputdomain}의 zone 파일 소유자 및 그룹 권한을 설정합니다."
        chown root:named /var/named/${_inputdomain}.zone
        chmod 640 /var/named/${_inputdomain}.zone

        rndc reload
    done
}

add_reverse_zone() {
    local _inputip
    local -a _iparr=() # 입력 받은 ip를 점을 기준으로 분리한 배열
    local _inputdomain
    local _inputservice
    local _serial=$(date +%Y%m%d)01
    local _hostoctet
    while :
    do
        _inputip=""
        _iparr=()
        _inputdomain=""
        _inputservice=""
        _hostoctet=""

        echo "============================================"
        echo "IP를 입력해주세요"
        echo "(예 : 192.168.10.125)"
        echo "q.이전 메뉴 복귀"
        echo "============================================"
        read -p "IP : " _inputip
        if [ "$_inputip" == "q" ]; then return 0
        elif ! check_ip "$_inputip"; then continue; fi
        _iparr=( $(split_dot "$_inputip") )
        _hostoctet=${_iparr[3]}
        # zone 선언 검사
        local _reverseip="${_iparr[2]}.${_iparr[1]}.${_iparr[0]}"   # ip 대역대
        if ! grep -E "^zone[[:space:]]+\"${_reverseip}\.in-addr\.arpa\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then    # zone으로 시작하고 "${_reverseip}\.in-addr\.arpa\" IN"으로 끝나는 줄.
            echo "${_reverseip} 대역대는 선언되지 않았습니다."

            # rfc1912.zones 파일에 선언 추가
            echo "rfc1912.zones에 ${_reverseip} 대역대를 선언합니다."
            create_zone_declaration "${_reverseip}.in-addr.arpa" "${_reverseip}.rev"
        fi

        while :
        do
            echo "============================================"
            echo "기준 도메인을 입력해주세요"
            echo "(www와 같은 Host Name을 제외하고 입력해야합니다. 예 : naver.com)"
            echo "q.이전 메뉴 복귀"
            echo "============================================"
            read -p "도메인 : " _inputdomain
            if [ "$_inputdomain" == "q" ]; then return 0
            fi
            break
        done

        # read -p "서비스를 입력해주세요 (www, mail 등 / 이전 메뉴 복귀 q) : " _inputservice
        # if [ "$_inputservice" == "q" ]; then return 0; fi

        # zone 파일 검사 (/var/named/)
        if [ -f "/var/named/${_reverseip}.rev" ]; then
            echo "${_reverseip}.rev 파일이 이미 존재합니다."
            # _hostoctet 중복 검사
            if grep -E "^${_hostoctet}[[:space:]]+IN[[:space:]]+PTR" "/var/named/${_reverseip}.rev" &>> "$LOG_FILE"; then
                echo "이미 ${_hostoctet}이 중복되어 있습니다."
                echo "해당 ip는 사용할 수 없습니다. 삭제하고 다시 시도해주세요."
                continue
            fi
            cat << EOF >> "/var/named/${_reverseip}.rev"
${_hostoctet}    IN PTR  ns1.${_inputdomain}.
EOF
        else    # zone 파일이 없을 경우
            echo "${_reverseip}.rev 파일이 존재하지 않습니다. 새로 생성합니다."
            cat << EOF > "/var/named/${_reverseip}.rev"
\$TTL 3H
@       IN SOA  ns1.${_inputdomain}. adminemail. (
                                        ${_serial}   ; serial
                                        1D          ; refresh
                                        1H          ; retry
                                        1W          ; expire
                                        3H          ; minimum
                                        )
        IN NS   ns1.${_inputdomain}.

; PTR 레코드
EOF
            # printf "%-7s IN PTR    %s\n" "$_hostoctet" "ns1.$_inputdomain." >> "/var/named/${_reverseip}.rev"
            # printf "%-7s IN PTR    %s\n" "$_hostoctet" "$_inputdomain." >> "/var/named/${_reverseip}.rev"
            # printf "%-7s IN PTR    %s\n" "$_hostoctet" "$_inputservice.$_inputdomain." >> "/var/named/${_reverseip}.rev"
            # zone 파일 소유자 및 그룹 권한 설정
            echo "${_reverseip}의 zone 파일 소유자 및 그룹 권한을 설정합니다."
            chown root:named /var/named/${_reverseip}.rev
            chmod 640 /var/named/${_reverseip}.rev
        fi
    echo "${_inputip} 역방향 zone 생성을 완료하였습니다."
    rndc reload
    done
}

# domain을 변수로 받아 해당 도메인을 삭제
domain_delete_zone() {
    local _inputdomain=$1
    local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)/zonefile"

    # zone 선언 확인
    if ! grep -E "^zone[[:space:]]+\"${_inputdomain}\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
        echo "${_inputdomain}은 named.rfc1912.zones에 선언되지 않았습니다."
        return 1
    fi

    # 도메인의 zone 파일 검사 (/var/named/)
    if [ ! -f "/var/named/${_inputdomain}.zone" ]; then
        echo "${_inputdomain}.zone 파일이 존재하지 않습니다."
        echo "해당 도메인은 등록되지 않았습니다."
        return 1
    fi

    # rfc1912.zones 파일에서 해당 도메인을 삭제
    delete_zone_declaration "$_inputdomain"

    # zone 파일을 백업 후 삭제
    mkdir -p "$_backuppath" &>> "$LOG_FILE"
    cp "/var/named/${_inputdomain}.zone" "$_backuppath/${_inputdomain}.zone_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    echo "${_inputdomain}.zone 파일이 백업되었습니다. (백업 위치 : $_backuppath/${_inputdomain}.zone_$(date +%Y%m%d_%H%M).bak)"
    rm -rf "/var/named/${_inputdomain}.zone"
    echo "${_inputdomain} 도메인이 삭제되었습니다."
    rndc reload
}

# 네트워크를 변수로 받아 해당 역방향 네트워크를 전체 삭제 (네트워크 대역대 삭제)
network_delete_zone() {
    local _inputip="${1}.255"    # $1 : 네트워크 주소 (예: 192.168.10)
    if ! check_ip "$_inputip"; then return 1; fi
    local -a _iparr
    _iparr=( $(split_dot "$_inputip") )
    local _reverseip="${_iparr[2]}.${_iparr[1]}.${_iparr[0]}"
    local _revfile="/var/named/${_reverseip}.rev"
    local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)"

    # zone 선언 확인
    if ! grep -E "^zone[[:space:]]+\"${_reverseip}\.in-addr\.arpa\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
        echo "${_reverseip}.in-addr.arpa 는 named.rfc1912.zones에 선언되지 않았습니다."
        echo "${_reverseip} 대역대는 등록되지 않았습니다."
        return 1
    fi

    # rfc1912.zones에서 해당 역방향 선언 삭제 (백업 후)
    delete_zone_declaration "${_reverseip}.in-addr.arpa"

    # zone 파일 확인
    if [ ! -f "$_revfile" ]; then
        echo "${_reverseip}.rev 파일이 존재하지 않습니다."
        echo "${_reverseip} 네트워크는 등록되지 않았습니다."
        return 1
    fi

    # zone 파일 백업 후 삭제
    mkdir -p "$_backuppath/zonefile" &>> "$LOG_FILE"
    cp "$_revfile" "$_backuppath/zonefile/${_reverseip}.rev_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    echo "${_reverseip}.rev 파일이 백업되었습니다. (백업 위치 : $_backuppath/zonefile/)"
    rm -f "$_revfile"
    echo "${_reverseip}.in-addr.arpa 역방향 네트워크가 삭제되었습니다."
    rndc reload
}

# TODO : delete_reverse_host와 통합
hostip_delete_zone() {
    local _inputnetwork=$1
    local -a _iparr
    _iparr=( $(split_dot "$_inputnetwork") )
    local _reverseip="${_iparr[2]}.${_iparr[1]}.${_iparr[0]}"
    local _revfile="/var/named/${_reverseip}.rev"
    local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)"

    # zone 선언 확인
    if ! grep -E "^zone[[:space:]]+\"${_reverseip}\.in-addr\.arpa\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
        echo "${_reverseip}.in-addr.arpa는 named.rfc1912.zones에 선언되지 않았습니다."
        echo "${_reverseip} 대역대는 등록되지 않았습니다."
        return 1
    fi

    while :
    do
        # TODO : 호스트 목록 조회
        echo "============================================"
        echo "삭제할 호스트 IP를 입력해주세요 (현재 입력한 네트워크 : $_inputnetwork)"
        echo "전체 IP의 마지막 부분만 입력해야합니다. 예 : 192.168.10.125의 125 부분"
        echo "q. 이전 메뉴 복귀"
        echo "============================================"
        read -p "호스트 IP : " _inputhost
        if [ "$_inputhost" == "q" ]; then return 0
        elif ! check_ip "${_inputnetwork}.${_inputhost}"; then
            echo "IP : ${_inputnetwork}.${_inputhost}"
            echo "잘못된 IP 형식입니다. 다시 입력해주세요."
            continue
        fi

        # 백업 파일 생성
        mkdir -p "$_backuppath/zonefile" &>> "$LOG_FILE"
        cp "$_revfile" "$_backuppath/zonefile/${_reverseip}.rev_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
        echo "${_reverseip}.rev 파일이 백업되었습니다. (백업 위치 : $_backuppath/zonefile/)"

        # 시리얼 번호 변경 필수
        update_serial "$_revfile"

        # zone 파일에서 해당 호스트 삭제
        sed -Ei "/^${_inputhost}[[:space:]]+IN[[:space:]]+PTR/d" "$_revfile"
        echo "${_inputnetwork}.${_inputhost} 호스트가 삭제되었습니다."
        rndc reload
    done
}

# rfc1912.zones에 zone 선언 블록을 추가
create_zone_declaration() {
    local _zone=$1
    local _zonefile=$2
    local _type=$(get_dns_type)
    local _masterip=$(awk -F':' '/MASTER_IP/ {print $2}' "${SCRIPT_DIR}/dns_data.txt")
    local _slaveip=$(awk -F':' '/SLAVE_IP/ {print $2}' "${SCRIPT_DIR}/dns_data.txt")

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

    update_decl_serial "${SCRIPT_DIR}/dns_data.txt"
}

# 존 선언 삭제 ($1 : 삭제할 도메인 / 네트워크 IP (in-addr.arpa 포함))
delete_zone_declaration() {
    local _target=$1
    local _startline=0
    local _endline=0

    _startline=$(grep -En "^zone[[:space:]]+\"$_target\"[[:space:]]+IN" /etc/named.rfc1912.zones | cut -d: -f1)
    if [ ! -n "$_startline" ]; then return 1; fi

    # 시작 행 이후에 나오는 '첫 번째 다음 zone'의 행 번호 찾기
    _endline=$(tail -n +$((_startline + 1)) /etc/named.rfc1912.zones | grep -En "^zone[[:space:]]+\"" | head -1 | cut -d: -f1)
    
    if [ -n "$_endline" ]; then
        _endline=$((_startline + _endline - 1))
    else
        _endline=$(wc -l /etc/named.rfc1912.zones | awk '{print $1}')
    fi

    # 백업
    local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)"
    mkdir -p "$_backuppath/rfc1912.zones/" &>> "$LOG_FILE"
    cp "/etc/named.rfc1912.zones" "$_backuppath/rfc1912.zones/rfc1912.zones_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"

    # 삭제
    sed -i "${_startline},${_endline}d" /etc/named.rfc1912.zones
    echo "${_target} 존 선언이 삭제되었습니다."

    update_decl_serial "${SCRIPT_DIR}/dns_data.txt"
}

# 도메인, 서비스, ip를 받는 서비스 추가 함수
add_forward_service() {
    local _domain=$1
    local _service=$2
    local _ip=$3
    local _zonefile="/var/named/${_domain}.zone"
    local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)/zonefile"

    # ip 유효성 체크
    if ! check_ip "$_ip"; then return 1; fi

    # service 중복 검사
    if grep -E "^${_service}[[:space:]]+IN[[:space:]]+A" "$_zonefile" &>> "$LOG_FILE"; then
        echo "${_service} 서비스가 이미 등록되었습니다."
        return 1
    fi

    # 백업 파일 생성
    mkdir -p "$_backuppath" &>> "$LOG_FILE"
    cp "$_zonefile" "$_backuppath/${_domain}.zone_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    
    # 시리얼 변경
    update_serial "$_zonefile"
    
    # 서비스 추가
    printf "%-7s IN A    %s\n" "$_service" "$_ip" >> "$_zonefile"
    echo "${_service} 서비스가 추가되었습니다."
    rndc reload
}

# 도메인, 서비스, ip를 받는 서비스 삭제 함수
delete_forward_service() {
    local _domain=$1
    local _service=$2
    local _zonefile="/var/named/${_domain}.zone"
    local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)/zonefile"

    # service 중복 검사
    if ! grep -E "^${_service}[[:space:]]+IN[[:space:]]+A" "$_zonefile" &>> "$LOG_FILE"; then
        echo "${_service} 서비스가 이미 등록되지 않았습니다."
        return 1
    fi

    # 백업 파일 생성
    mkdir -p "$_backuppath" &>> "$LOG_FILE"
    cp "$_zonefile" "$_backuppath/${_domain}.zone_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    
    # 시리얼 변경
    update_serial "$_zonefile"
    
    # 서비스 삭제
    sed -Ei "/^${_service}[[:space:]]+IN[[:space:]]+A/d" "$_zonefile"
    echo "${_service} 서비스가 삭제되었습니다."
    rndc reload
}

# 도메인(+서비스), 네트워크, 호스트ip를 받는 hostIP 추가 함수
add_reverse_host() {
    local _domain=$1
    local _network=$2
    local _hostip=$3
    local _revfile="/var/named/${_network}.rev"
    local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)/zonefile"

    # ip 유효성 체크 (굳이 네트워크를 뒤집을 필요 없음)
    #_iparr=( $(split_dot "$_network") )
    #local _forwardip="${_iparr[2]}.${_iparr[1]}.${_iparr[0]}"   # ip 대역대
    echo "$_network.$_hostip"
    if ! check_ip "$_network.$_hostip"; then return 1; fi

    # hostip 중복 검사
    if grep -E "^${_hostip}[[:space:]]+IN[[:space:]]+PTR" "$_revfile" &>> "$LOG_FILE"; then
        echo "이미 ${_hostip}는 사용 중입니다."
        echo "다시 시도해주세요."
        return 1
    fi

    # 백업 파일 생성
    mkdir -p "$_backuppath" &>> "$LOG_FILE"
    cp "$_revfile" "$_backuppath/${_network}.rev_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    
    # 시리얼 변경
    update_serial "$_revfile"
    
    # 서비스 추가
    printf "%-7s IN PTR    %s\n" "$_hostip" "$_domain" >> "$_revfile"
    echo "${_hostip}가 추가되었습니다."
    rndc reload
}

# 네트워크, 호스트ip를 받는 hostIP 삭제 함수
delete_reverse_host() {
    local _network=$1
    local _hostip=$2
    local _revfile="/var/named/${_network}.rev"
    local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)/zonefile"

    # hostip 중복 검사
    if ! grep -E "^${_hostip}[[:space:]]+IN[[:space:]]+PTR" "$_revfile" &>> "$LOG_FILE"; then
        echo "${_hostip}는 미사용 중입니다."
        echo "다시 입력해주세요."
        return 1
    elif ! check_ip "${_network}.${_hostip}"; then
        echo "IP : ${_network}.${_hostip}"
        echo "잘못된 IP 형식입니다. 다시 입력해주세요."
        return 1
    fi

    # 백업 파일 생성
    mkdir -p "$_backuppath" &>> "$LOG_FILE"
    cp "$_revfile" "$_backuppath/${_network}.rev_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    
    # 시리얼 변경
    update_serial "$_revfile"
    
    # 서비스 삭제
    sed -Ei "/^${_hostip}[[:space:]]+IN[[:space:]]+PTR/d" "$_revfile"
    echo "${_hostip}가 삭제되었습니다."
    rndc reload
}