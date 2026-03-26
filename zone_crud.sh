#!/bin/bash

select_add_zone() {
    local input
    while :
    do
        echo "============================================"
        echo "1. 정방향 생성"
        echo "2. 역방향 생성"
        echo "0. 이전 메뉴 복귀"
        echo "============================================"
        read -p "원하는 작업을 선택하세요 : " input
        case $input in
            1)
                add_forward_zone
                zone_list_reload zonearr
                ;;
            2)
                add_reverse_zone
                zone_list_reload zonearr
                ;;
            0) 
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
    local inputdomain    # 입력 받을 도메인
    local inputip   # 입력 받을 ip
    local servicearr=() # 입력 받을 서비스의 배열
    local serial=$(date +%Y%m%d)01  # zone파일 시리얼 넘버

    while :
    do
        echo "============================================"
        echo "기준 도메인을 입력해주세요"
        echo "(www와 같은 Host Name을 제외하고 입력해야합니다. 예 : naver.com)"
        echo "0.이전 메뉴 복귀"
        echo "============================================"
        read -p "도메인 : " inputdomain
        if [ "$inputdomain" == "0" ]; then return 0
        fi
        
        # 도메인 유효성 검사 TODO
        
        # zone 선언 파일 검사 (/etc/named.rfc1912.zone)
        if grep -E "^zone \"${inputdomain}\" IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
            echo "이미 ${inputdomain} 도메인이 선언되어 있습니다."
            echo "도메인을 삭제하고 다시 입력해주세요"
            continue
        fi   

        # zone 파일 검사 (/var/named/)
        if [ -f "/var/named/${inputdomain}.zone" ]; then
            echo "${inputdomain}.zone 파일이 이미 존재합니다."
            echo "해당 zone 파일을 백업하고 새로 생성하겠습니다."
            local backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)/zonefile"
            mkdir -p "$backuppath" &>> "$LOG_FILE"
            cp "/var/named/${inputdomain}.zone" "$backuppath/${inputdomain}.zone_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
            echo "${inputdomain}.zone 파일이 백업되었습니다. (백업 위치 : $backuppath/${inputdomain}.zone_$(date +%Y%m%d_%H%M).bak)"
            rm -rf "/var/named/${inputdomain}.zone"
        fi

        # ip 입력
        while :
        do
            read -p "IP를 입력해주세요 (이전 메뉴로 돌아가려면 0 입력) : " inputip
            if [ "$inputip" == "0" ]; then return 0
            elif ! check_ip "$inputip"; then continue
            fi
            break
        done
        # 서비스 입력
        servicearr=()
        while :
        do
            read -p "서비스를 입력해주세요 (www, mail, @ 등 / 다음 단계로 진행하려면 1 입력) : " inputservice
            if [ "$inputservice" == "1" ]; then break
            fi
            servicearr+=("$inputservice")
            echo "현재 입력된 서비스 : ${servicearr[@]}"
        done

        # rfc1912.zones 파일에 선언 추가
        echo "도메인 ${inputdomain}을 추가합니다."
        cat << EOF >> /etc/named.rfc1912.zones

zone "${inputdomain}" IN {
        type master;
        file "${inputdomain}.zone";
        allow-update {none;};
};
EOF
        # zone 파일 생성
        echo "${inputdomain}의 Zone 파일을 생성합니다."
        cat << EOF > /var/named/${inputdomain}.zone
\$TTL 3H
@       IN SOA  ns1.${inputdomain}. adminemail. (
                                        ${serial}   ; serial
                                        1D          ; refresh
                                        1H          ; retry
                                        1W          ; expire
                                        3H          ; minimum
                                        )
        IN NS   ns1.${inputdomain}.

ns1     IN A    ${DNS_IP}
EOF
        # zone 파일에 서비스 추가
        for service in "${servicearr[@]}"; do
            printf "%-7s IN A    %s\n" "$service" "$inputip" >> /var/named/${inputdomain}.zone
        done

        echo "${inputdomain}.zone 파일이 생성을 완료하였습니다."

        # zone 파일 소유자 및 그룹 권한 설정
        echo "${inputdomain}의 zone 파일 소유자 및 그룹 권한을 설정합니다."
        chown root:named /var/named/${inputdomain}.zone
        chmod 640 /var/named/${inputdomain}.zone
    done
}

add_reverse_zone() {
    local inputip
    local -a iparr=() # 입력 받은 ip를 점을 기준으로 분리한 배열
    local inputdomain
    local inputservice
    local serial=$(date +%Y%m%d)01
    local hostoctet
    while :
    do
        inputip=""
        iparr=()
        inputdomain=""
        inputservice=""
        hostoctet=""

        echo "============================================"
        echo "IP를 입력해주세요"
        echo "(예 : 192.168.10.125)"
        echo "0.이전 메뉴 복귀"
        echo "============================================"
        read -p "IP : " inputip
        if [ "$inputip" == "0" ]; then return 0
        elif ! check_ip "$inputip"; then continue
        fi
        iparr=( $(split_dot "$inputip") )
        hostoctet=${iparr[3]}
        # zone 선언 검사
        local reverseip="${iparr[2]}.${iparr[1]}.${iparr[0]}"   # ip 대역대
        if ! grep -E "^zone \"${reverseip}\.in-addr\.arpa\" IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then    # zone으로 시작하고 "${reverseip}\.in-addr\.arpa\" IN"으로 끝나는 줄.
            echo "${reverseip} 대역대는 선언되지 않았습니다."
            
            # rfc1912.zones 파일에 선언 추가
            echo "rfc1912.zones에 ${reverseip} 대역대를 선언합니다."
            cat << EOF >> /etc/named.rfc1912.zones

zone "${reverseip}.in-addr.arpa" IN {
        type master;
        file "${reverseip}.rev";
        allow-update { none; };
};
EOF
        fi

        while :
        do
            echo "============================================"
            echo "기준 도메인을 입력해주세요"
            echo "(www와 같은 Host Name을 제외하고 입력해야합니다. 예 : naver.com)"
            echo "0.이전 메뉴 복귀"
            echo "============================================"
            read -p "도메인 : " inputdomain
            if [ "$inputdomain" == "0" ]; then return 0
            fi
            break
        done

        read -p "서비스를 입력해주세요 (www, mail, @ 등 / 이전 메뉴 복귀 0) : " inputservice
        if [ "$inputservice" == "0" ]; then return 0
        fi

        echo "DEBUG: 검사할 경로 = /var/named/${reverseip}.rev"
        echo "DEBUG: 파일 존재 여부 = $([ -f "/var/named/${reverseip}.rev" ] && echo '존재' || echo '없음')"

        # zone 파일 검사 (/var/named/)
        if [ -f "/var/named/"${reverseip}".rev" ]; then
            echo "${reverseip}.rev 파일이 이미 존재합니다."
            # hostoctet 중복 검사
            if grep -E "^${hostoctet}[[:space:]]+IN[[:space:]]+PTR" "/var/named/"${reverseip}".rev" &>> "$LOG_FILE"; then
                echo "이미 ${hostoctet}이 중복되어 있습니다."
                echo "해당 ip는 사용할 수 없습니다. 삭제하고 다시 시도해주세요."
                continue
            fi
            cat << EOF >> "/var/named/${reverseip}.rev"
${hostoctet}    IN PTR  ${inputservice}.${inputdomain}.
EOF
        else    # zone 파일이 없을 경우
            echo "${reverseip}.rev 파일이 존재하지 않습니다. 새로 생성합니다."
            cat << EOF > "/var/named/${reverseip}.rev"
\$TTL 3H
@       IN SOA  ns1.${inputdomain}. adminemail. (
                                        ${serial}   ; serial
                                        1D          ; refresh
                                        1H          ; retry
                                        1W          ; expire
                                        3H          ; minimum
                                        )
        IN NS   ns1.${inputdomain}.

; PTR 레코드
${hostoctet}    IN PTR  ${inputservice}.${inputdomain}.
EOF
            # zone 파일 소유자 및 그룹 권한 설정
            echo "${reverseip}의 zone 파일 소유자 및 그룹 권한을 설정합니다."
            chown root:named /var/named/${reverseip}.rev
            chmod 640 /var/named/${reverseip}.rev
        fi
    echo "${inputip} 역방향 zone 생성을 완료하였습니다."
    done
}

select_delete_zone() {
    while :   
    do
        sleep 1
        clear
        show_zone_list zonearr ${currentpage}
        echo "[. 다음 페이지"
        echo "]. 이전 페이지" 
        echo ":숫자. 해당 번호의 페이지로 이동"
        echo "-----------------------------------------------"
        echo :숫자. 해당 번호의 ZONE 삭제
        echo "a. 도메인을 입력하여 삭제 (정방향 삭제)"
        echo "b. 역방향 ip를 입력하여 삭제 (역방향 삭제)"
        echo "0. 메인 메뉴 복귀"
        echo "==============================================="
        read -p "원하는 작업을 선택하세요 : " input
        case "$input" in 
            a)
                echo "============================================"
                echo "기준 도메인을 입력해주세요"
                echo "(www와 같은 Host Name을 제외하고 입력해야합니다. 예 : naver.com)"
                echo "0.이전 메뉴 복귀"
                echo "============================================"
                read -p "도메인 : " inputdomain
                if [ "$inputdomain" == "0" ]; then continue
                fi
                domain_delete_zone "$inputdomain"
                ;;
            b)
                echo "============================================"
                echo "역방향 삭제할 IP를 입력해주세요"
                echo "(예 : 192.168.10.125 — 해당 IP의 대역 기준으로 삭제)"
                echo "0.이전 메뉴 복귀"
                echo "============================================"
                read -p "IP : " inputip
                if [ "$inputip" == "0" ]; then continue
                elif ! check_ip "$inputip"; then continue
                fi
                ip_delete_zone "$inputip"
                ;;
            0)
                return 0
                ;;
            *)
                echo "잘못된 입력입니다. 다시 시도해주세요."
                ;;
        esac
    done
}

# domain을 변수로 받아 해당 도메인을 삭제
domain_delete_zone() {
    local inputdomain=$1
    local zonefile=""
    local backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)"

    # zone 선언 확인
    if ! grep -E "^zone \"${inputdomain}\" IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
        echo "${inputdomain}은 named.rfc1912.zones에 선언되지 않았습니다."         
        return 1
    fi
    
    # 도메인의 zone 파일 검사 (/var/named/)
    if [ ! -f "/var/named/${inputdomain}.zone" ]; then
        echo "${inputdomain}.zone 파일이 존재하지 않습니다."
        echo "해당 도메인은 등록되지 않았습니다."
        return 1
    fi

    # rfc1912.zones 파일에서 해당 도메인을 삭제
    mkdir -p "$backuppath/rfc1912.zones/" &>> "$LOG_FILE"
    cp "/etc/named.rfc1912.zones" "$backuppath/rfc1912.zones/rfc1912.zones_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    sed -i "/^zone \"${inputdomain}\" IN/, /};/d" /etc/named.rfc1912.zones
    # 해당 zone 파일을 삭제
    local backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)/zonefile"
    mkdir -p "$backuppath" &>> "$LOG_FILE"
    cp "/var/named/${inputdomain}.zone" "$backuppath/${inputdomain}.zone_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    echo "${inputdomain}.zone 파일이 백업되었습니다. (백업 위치 : $backuppath/${inputdomain}.zone_$(date +%Y%m%d_%H%M).bak)"
    rm -rf "/var/named/${inputdomain}.zone"
    echo "${inputdomain} 도메인이 삭제되었습니다."
}

# ip를 변수로 받아 해당 역방향 zone을 삭제
ip_delete_zone() {
    local inputip=$1
    local -a iparr
    iparr=( $(split_dot "$inputip") )
    local reverseip="${iparr[2]}.${iparr[1]}.${iparr[0]}"
    local revfile="/var/named/${reverseip}.rev"
    local backuppath="$SCRIPT_DIR/dns_backup_$(date +%Y%m%d)"

    # zone 선언 확인
    if ! grep -E "^zone \"${reverseip}\.in-addr\.arpa\" IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
        echo "${reverseip}.in-addr.arpa 는 named.rfc1912.zones에 선언되지 않았습니다."
        return 1
    fi

    # zone 파일 확인
    if [ ! -f "$revfile" ]; then
        echo "${reverseip}.rev 파일이 존재하지 않습니다."
        return 1
    fi

    # rfc1912.zones에서 해당 역방향 선언 삭제 (백업 후)
    mkdir -p "$backuppath/rfc1912.zones/" &>> "$LOG_FILE"
    cp /etc/named.rfc1912.zones "$backuppath/rfc1912.zones/rfc1912.zones_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    sed -i "/^zone \"${reverseip}\.in-addr\.arpa\" IN/, /};/d" /etc/named.rfc1912.zones

    # zone 파일 백업 후 삭제
    mkdir -p "$backuppath/zonefile" &>> "$LOG_FILE"
    cp "$revfile" "$backuppath/zonefile/${reverseip}.rev_$(date +%Y%m%d_%H%M).bak" &>> "$LOG_FILE"
    echo "${reverseip}.rev 파일이 백업되었습니다. (백업 위치 : $backuppath/zonefile/)"
    rm -f "$revfile"
    echo "${reverseip}.in-addr.arpa 역방향 zone이 삭제되었습니다."
}