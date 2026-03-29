#!/bin/bash
# ============================================================
# select_add_zone()        : 정방향/역방향 Zone 추가 메뉴
# select_delete_zone()     : Zone 삭제 메뉴 (도메인 또는 네트워크 기준)
# select_update_zone()     : Zone 수정 메뉴 [미구현]
# add_forward_zone()       : 정방향 Zone 선언 및 zone 파일 생성
# add_reverse_zone()       : 역방향 Zone 선언 및 .rev 파일 생성/수정
# domain_delete_zone()     : 도메인 기준으로 정방향 Zone 삭제
# network_delete_zone()    : 네트워크 대역 기준으로 역방향 Zone 전체 삭제
# hostip_delete_zone()     : 역방향 Zone에서 특정 호스트 IP 레코드만 삭제
# delete_zone_declaration(): rfc1912.zones에서 zone 선언 블록 삭제
# update_service()         : 서비스 수정 [미구현]
# ============================================================

select_add_zone() {
    local _input
    while :
    do
        echo "============================================"
        echo "1. 정방향 생성"
        echo "2. 역방향 생성"
        echo "q. 이전 메뉴 복귀"
        echo "============================================"
        read -p "원하는 작업을 선택하세요 : " _input
        case $_input in
            1)
                add_forward_zone
                ;;
            2)
                add_reverse_zone
                ;;
            "q")
                return 0
                ;;
            *)
                echo "잘못된 입력입니다. 다시 시도해주세요."
                ;;
        esac
    done
}

select_delete_zone() {
    local -n _refzonearr=$1
    while :   
    do
        sleep 2 && clear
        show_zone_list "${!_refzonearr}" ${currentpage}
        echo "[. 다음 페이지    | ]. 이전 페이지    | :숫자. 해당 번호의 페이지로 이동"
        echo "-----------------------------------------------"
        echo :숫자. 해당 번호의 ZONE 삭제
        echo "1. 도메인을 입력하여 삭제 (정방향 삭제)"
        echo "2. 네트워크 주소를 입력하여 삭제 (역방향 HOST, 네트워크 삭제)"
        echo "q. 메인 메뉴 복귀"
        echo "==============================================="
        read -p "원하는 작업을 선택하세요 : " _input
        case "$_input" in
            1)
                echo "============================================"
                echo "기준 도메인을 입력해주세요"
                echo "(www와 같은 서비스 이름을 제외하고 입력해야 합니다. 예 : naver.com)"
                echo "0. 이전 메뉴 복귀"
                echo "============================================"
                read -p "도메인 : " _inputdomain
                if [ "$_inputdomain" == "0" ]; then continue
                fi
                domain_delete_zone "$_inputdomain"
                zone_list_reload "${!_refzonearr}"
                ;;
            2)
                echo "============================================"
                echo "삭제할 네트워크 주소를 입력해주세요"
                echo "(호스트를 제외하고 입력해야 합니다. 예 : 192.168.10)"
                echo "q. 이전 메뉴 복귀"
                echo "============================================"
                read -p "네트워크 : " _inputnetwork
                if [ "$_inputnetwork" == "q" ]; then continue
                fi
                echo "============================================"
                echo "1. 네트워크 주소 삭제"
                echo "2. 호스트 주소 삭제"
                echo "q. 메뉴 복귀"
                echo "============================================"
                read -p "원하는 작업을 선택하세요 : " _input
                case "$_input" in
                    1)
                        network_delete_zone "$_inputnetwork"
                        zone_list_reload "${!_refzonearr}"
                        ;;
                    2)
                        hostip_delete_zone "$_inputnetwork"
                        zone_list_reload "${!_refzonearr}"
                        ;;
                    "q")
                        continue
                        ;;
                    *)
                        echo "잘못된 입력입니다. 다시 시도해주세요."
                        ;;
                esac
                ;;
            "q")
                return 0
                ;;
            *)
                echo "잘못된 입력입니다. 다시 시도해주세요."
                ;;
        esac
    done
}

select_update_zone() {
    local -n _refzonearr=$1
    while :
    do
        sleep 2 && clear
        show_zone_list "${!_refzonearr}" ${currentpage}
        echo "[. 다음 페이지    | ]. 이전 페이지    | :숫자. 해당 번호의 페이지로 이동"
        echo "-----------------------------------------------"
        echo :숫자. 해당 번호의 ZONE 삭제
        echo "1. 서비스 수정"
        echo "2. 호스트 수정"
        echo "3. zone 파일 수정"
        echo "q. 메인 메뉴 복귀"
        echo "==============================================="
        read -p "원하는 작업을 선택하세요 : " _input
        case "$_input" in
            1)
                echo "============================================"
                echo ""
                echo ""
                echo "============================================"
                read -p "도메인 : " _inputdomain
                ;;
            2)
                
                ;;
            3)
                
                ;;
            "q")
                return 0
                ;;
            *)
                echo "잘못된 입력입니다. 다시 시도해주세요."
                ;;
        esac
    done
}

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
        if grep -E "^zone \"${_inputdomain}\" IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
            echo "이미 ${_inputdomain} 도메인이 선언되어 있습니다."
            echo "도메인을 삭제하고 다시 입력해주세요"
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

        # 서비스 입력
        _servicearr=()
        while :
        do
            read -p "서비스를 입력해주세요 (www, mail, @ 등 / 다음 단계로 진행하려면 1 입력) : " _inputservice
            if [ "$_inputservice" == "1" ]; then break; fi
            _servicearr+=("$_inputservice")
            echo "현재 입력된 서비스 : ${_servicearr[@]}"
        done

        # rfc1912.zones 파일에 선언 추가
        echo "도메인 ${_inputdomain}을 추가합니다."
        cat << EOF >> /etc/named.rfc1912.zones

zone "${_inputdomain}" IN {
        type master;
        file "${_inputdomain}.zone";
        allow-update {none;};
};
EOF
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
        if ! grep -E "^zone \"${_reverseip}\.in-addr\.arpa\" IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then    # zone으로 시작하고 "${_reverseip}\.in-addr\.arpa\" IN"으로 끝나는 줄.
            echo "${_reverseip} 대역대는 선언되지 않았습니다."

            # rfc1912.zones 파일에 선언 추가
            echo "rfc1912.zones에 ${_reverseip} 대역대를 선언합니다."
            cat << EOF >> /etc/named.rfc1912.zones

zone "${_reverseip}.in-addr.arpa" IN {
        type master;
        file "${_reverseip}.rev";
        allow-update { none; };
};
EOF
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

        read -p "서비스를 입력해주세요 (www, mail, @ 등 / 이전 메뉴 복귀 q) : " _inputservice
        if [ "$_inputservice" == "q" ]; then return 0; fi

        echo "DEBUG: 검사할 경로 = /var/named/${_reverseip}.rev"
        echo "DEBUG: 파일 존재 여부 = $([ -f "/var/named/${_reverseip}.rev" ] && echo '존재' || echo '없음')"

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
${_hostoctet}    IN PTR  ${_inputservice}.${_inputdomain}.
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
${_hostoctet}    IN PTR  ${_inputservice}.${_inputdomain}.
EOF
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
    if ! grep -E "^zone \"${_inputdomain}\" IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
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
    if ! grep -E "^zone \"${_reverseip}\.in-addr\.arpa\" IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
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

hostip_delete_zone() {
    local _inputnetwork=$1
    local -a _iparr
    _iparr=( $(split_dot "$_inputnetwork") )
    local _reverseip="${_iparr[2]}.${_iparr[1]}.${_iparr[0]}"
    local _revfile="/var/named/${_reverseip}.rev"
    local _backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)"

    # zone 선언 확인
    if ! grep -E "^zone \"${_reverseip}\.in-addr\.arpa\" IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
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

        # zone 파일에서 해당 호스트 삭제 (백업)
        # 입력된 호스트로 시작하고 공백 상관없이 IN PTR에 패턴인 행을 삭제
        mkdir -p "$_backuppath/zonefile" &>> "$LOG_FILE"
        cp "$_revfile" "$_backuppath/zonefile/${_reverseip}.rev_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
        echo "${_reverseip}.rev 파일이 백업되었습니다. (백업 위치 : $_backuppath/zonefile/)"

        # 시리얼 번호 변경 필수
        local _serial=$(awk '/serial/ {print $1}' "$_revfile")
        local _newserial=$((_serial + 1))
        sed -i "s/${_serial}/${_newserial}/" "$_revfile"

        sed -i "/^${_inputhost}[[:space:]]\+IN[[:space:]]\+PTR/d" "$_revfile"
        echo "${_inputnetwork}.${_inputhost} 호스트가 삭제되었습니다."
        rndc reload
    done
}

# 존 선언 삭제 ($1 : 삭제할 도메인 / 네트워크 IP)
delete_zone_declaration() {
    local _target=$1
    local _startline=0
    local _endline=0

    _startline=$(grep -n "^zone[[:space:]]\+\"$_target\"[[:space:]]\+IN" /etc/named.rfc1912.zones | cut -d: -f1)
    if [ ! -n "$_startline" ]; then return 1; fi

    # 시작 행 이후에 나오는 '첫 번째 다음 zone'의 행 번호 찾기
    _endline=$(tail -n +$((_startline + 1)) /etc/named.rfc1912.zones | grep -n "^zone[[:space:]]\+\"" | cut -d: -f1)
    
    if [ -n "$_endline" ]; then
        _endline=$((_startline + _endline - 1))
    else
        _endline=$(wc -l /etc/named.rfc1912.zones | awk '{print $1}')
    fi

    # 백업
    mkdir -p "$backuppath/rfc1912.zones/" &>> "$LOG_FILE"
    cp "/etc/named.rfc1912.zones" "$backuppath/rfc1912.zones/rfc1912.zones_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"

    # 삭제
    sed -i "${_startline},${_endline}d" /etc/named.rfc1912.zones
    echo "${_target} 존 선언이 삭제되었습니다."
}

update_service() {
    
}

# TODO
# 서비스 네임과 도메인이 들어오면 서비스를 추가하는 함수
# 서비스 네임과 도메인이 들어오면 서비스를 삭제하는 함수
# 호스트와 네트워크가 들어오면 레코드를 추가하는 함수
# 호스트와 네트워크가 들어오면 레코드를 삭제하는 함수
# 존 파일 수정 (refresh, retry, expire, minimum)
# 환경설정 - named.conf 설정, listen-on port v6, allow-query, 슬레이브 서버 지정

# 슬레이브 변경
# named.conf : listen-on, allow-query 수정
# Slave 서버 rfc1912.zones 수정
# 자동으로 추가할 순 없을까?
# 안되면 정방향 도메인 연속입력, 역방향 네트워크 연속입력으로 처리

# 슬레이브 서버 지정
# ip를 입력한 후 zone 파일 리스트를 보여주고 연속으로 입력하면 (숫자로도 가능) 자동으로 기본값으로 추가하는 형식
