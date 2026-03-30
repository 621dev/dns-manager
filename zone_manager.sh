#!/bin/bash
# ============================================================
# manage_zone()    : Zone 목록을 페이지별로 출력하고 CRUD 메뉴를 처리하는 루프
# select_add_zone()        : 정방향/역방향 Zone 추가 메뉴
# select_delete_zone()     : Zone 삭제 메뉴 (도메인 또는 네트워크 기준)
# select_update_zone()     : Zone 수정 메뉴
# check_ip()       : IP 주소 형식 및 범위 유효성 검사 (4옥텟, 0~255, 선행 0 등)
# split_dot()      : 점(.) 기준으로 문자열을 분리하여 배열 출력
# zone_list_reload(): /etc/named.rfc1912.zones에서 zone 목록을 배열로 갱신
# show_zone_list() : zone 배열을 페이지 단위(7개)로 출력
# ============================================================

source "$SCRIPT_DIR/zone_crud.sh"

manage_zone(){
    local _input
    local -a _zonearr=()
    local _currentpage=0
    zone_list_reload _zonearr
    while :
    do
        sleep 1 && clear
        show_zone_list _zonearr ${_currentpage}
        echo "ZONE은 도메인과 IP 주소 간의 연결 정보를 담고 있는 파일입니다."
        echo "도메인이나 IP를 입력하여 ZONE을 추가, 수정, 삭제가 가능합니다."
        echo "-----------------------------------------------"
        echo "[. 다음 페이지    ]. 이전 페이지      :숫자. 해당 번호의 페이지로 이동"
        echo "-----------------------------------------------"
        echo "1. ZONE 조회 (미구현)"
        echo "2. ZONE 추가"
        echo "3. ZONE 수정"
        echo "4. ZONE 삭제"
        echo "q. 메인 메뉴 복귀"
        echo "==============================================="
        read -p "원하는 작업을 선택하세요 : " _input
        case "$_input" in
            1)
                echo "미구현 항목입니다."
                ;;
            2)
                select_add_zone
                zone_list_reload _zonearr
                ;;
            3)
                select_update_zone _zonearr
                zone_list_reload _zonearr
                ;;
            4)
                select_delete_zone _zonearr
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
    local _input
    while :
    do
        sleep 1 && clear
        show_zone_list "${!_refzonearr}" 0
        echo "-----------------------------------------------"
        echo "1. 서비스 수정"
        echo "2. 호스트 수정"
        echo "q. 이전 메뉴 복귀"
        echo "==============================================="
        read -p "원하는 작업을 선택하세요 : " _input
        case "$_input" in
            1)
                read -p "수정할 도메인을 입력해주세요 (q. 취소) : " _domain
                if [ "$_domain" == "q" ]; then continue; fi
                # zone 선언 파일 검사 (/etc/named.rfc1912.zone)
                if ! grep -E "^zone[[:space:]]+\"${_domain}\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
                    echo "${_domain} 도메인이 선언되어 있지 않습니다."
                    echo "정방향 ZONE을 생성해주세요"
                    continue
                fi
                # zone 파일 검사 (/var/named/)
                if [ ! -f "/var/named/${_domain}.zone" ]; then
                    echo "${_domain}.zone 파일이 존재하지 않습니다."
                    echo "해당 zone 파일을 생성해주세요."
                    continue
                fi
                while :
                do
                    echo "==============================================="
                    echo "현재 입력된 도메인 : ${_domain}"  # TODO : 서비스 목록도 보여줘야함
                    echo "-----------------------------------------------"
                    echo "1. 서비스 추가"
                    echo "2. 서비스 삭제"
                    echo "q. 이전 메뉴 복귀"
                    echo "==============================================="
                    read -p "원하는 작업을 선택하세요 : " _input
                    case "$_input" in
                        1)
                            while :
                            do
                                read -p "추가할 서비스의 IP 주소를 입력해주세요 (q. 취소) : " _ip
                                if [ "$_ip" == "q" ]; then break; fi  
                                read -p "추가할 서비스 이름을 입력해주세요 (q. 취소) : " _service
                                if [ "$_service" == "q" ]; then break; fi
                                # 실제 서비스 추가 구문
                                add_forward_service "$_domain" "$_service" "$_ip"
                            done
                            ;;
                        2)
                            while :
                            do
                                read -p "삭제할 서비스 이름을 입력해주세요 (q. 취소) : " _service
                                if [ "$_service" == "q" ]; then break; fi
                                # 실제 서비스 삭제 구문
                                delete_forward_service "$_domain" "$_service"
                            done
                            ;;
                        "q")
                            break
                            ;;
                        *)
                            echo "잘못된 입력입니다. 다시 시도해주세요."
                            ;;
                    esac
                done
                ;;
            2)
                echo "============================================"
                echo "수정할 네트워크 주소를 입력해주세요"
                echo "(호스트를 제외하고 입력해야 합니다. 예 : 192.168.10)"
                echo "q. 이전 메뉴 복귀"
                echo "============================================"
                read -p "네트워크 : " _inputnetwork
                if [ "$_inputnetwork" == "q" ]; then continue; fi

                _iparr=( $(split_dot "$_inputnetwork") )
                local _reverseip="${_iparr[2]}.${_iparr[1]}.${_iparr[0]}"   # ip 대역대
                # zone 선언 여부 (/etc/named.rfc1912.zone)
                if ! grep -E "^zone[[:space:]]+\"${_reverseip}\.in-addr\.arpa\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then    # zone으로 시작하고 "${_reverseip}\.in-addr\.arpa\" IN"으로 끝나는 줄.
                    echo "${_reverseip} 대역대는 선언되지 않았습니다."
                    continue
                fi

                # zone 파일 여부 (/var/named/)
                if [ ! -f "/var/named/${_reverseip}.rev" ]; then
                    echo "${_reverseip}.rev 파일이 존재하지 않습니다."
                    echo "해당 네트워크 대역의 역방향 ZONE을 생성해주세요."
                    continue
                fi

                while :
                do
                    echo "==============================================="
                    echo "현재 입력된 네트워크 : ${_inputnetwork} / ${_reverseip}"  # TODO : 호스트 목록도 보여줘야함
                    echo "-----------------------------------------------"
                    echo "1. 호스트 추가"
                    echo "2. 호스트 삭제"
                    echo "q. 이전 메뉴 복귀"
                    echo "==============================================="
                    read -p "원하는 작업을 선택하세요 : " _input
                    case "$_input" in
                        1)
                            while :
                            do
                                read -p "추가할 호스트 ip를 입력해주세요 (q. 취소) : " _hostip
                                if [ "$_hostip" == "q" ]; then break; fi  
                                read -p "추가할 도메인을 입력해주세요 (q. 취소 / 예 : www.naver.com) : " _domain
                                if [ "$_domain" == "q" ]; then break; fi
                                # 실제 서비스 추가 구문
                                add_reverse_host "$_domain" "$_reverseip" "$_hostip"
                            done
                            ;;
                        2)
                            while :
                            do
                                echo "============================================"
                                echo "삭제할 호스트 IP를 입력해주세요 (현재 입력한 네트워크 : $_network)"
                                echo "전체 IP의 마지막 부분만 입력해야합니다. 예 : 192.168.10.125의 125 부분"
                                echo "q. 이전 메뉴 복귀"
                                echo "============================================"
                                read -p "호스트 IP : " _hostip
                                if [ "$_hostip" == "q" ]; then break; fi
                                # 실제 서비스 삭제 구문
                                delete_reverse_host "$_reverseip" "$_hostip"
                            done
                            ;;
                        "q")
                            break
                            ;;
                        *)
                            echo "잘못된 입력입니다. 다시 시도해주세요."
                            ;;
                    esac
                done
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

# ip 유효성
check_ip() {
    local _inputip="$1"
    local -a _arrip
    _arrip=( $(split_dot "$_inputip") )

    # 1. 4개의 옥텟을 가짐.
    if [ ${#_arrip[@]} -ne 4 ]; then # ${#_arrip[@]} : 배열의 길이, '-ne' = '!=' : 숫자비교
        echo "IP 주소는 4개의 옥텟으로 구성되어야 합니다."
        return 1
    fi

    # 4. 0.0.0.0, 255.255.255.255 제외
    if [[ "$_inputip" == "0.0.0.0" || "$_inputip" == "255.255.255.255" ]]; then
        echo "IP 주소는 0.0.0.0 또는 255.255.255.255 일 수 없습니다."
        return 1
    fi

    for _octet in "${_arrip[@]}"; do
        if [[ ! "$_octet" =~ ^[0-9]+$ ]]; then #2. 옥텟은 숫자와 점으로만 구성.
            echo "IP 주소는 숫자와 점으로만 구성되어야 합니다."
            return 1
        elif (( _octet < 0 || _octet > 255 )); then #3. 각 옥텟은 0 ~ 255.
            echo "IP 주소의 각 옥텟은 0에서 255 사이여야 합니다."
            return 1
        elif [[ "$_octet" =~ ^0[0-9]+$ ]]; then #5. 10 이상일 때 앞 자리는 0이 아니어야 함.
            echo "0으로 시작하는 두 자리 숫자는 가질 수 없습니다."
            return 1
        fi
    done
    return 0
}

# 점을 기준으로 분리, $1 : 입력값
split_dot() {
    local _input="$1"
    local -a _temp_arr
    IFS='.' read -r -a _temp_arr <<< "$_input"
    # IFS : 쉘이 단어를 쪼갤 때 기준이 되는 구분자를 지정
    # read : 표준 입력으로 들어온 텍스트를 한 줄 읽음
    # -r : 특수 기호를 문자 그대로 취급
    # <<< : 오른쪽에 있는 문자열을 표준 입력으로 전달
    echo "${_temp_arr[@]}"
}

zone_list_reload() {
    local -n _refarr=$1  # nameref - 참조로 받음
    mapfile -t _refarr < <(awk -F'"' '/^zone "/ {print $2}' /etc/named.rfc1912.zones) 
    # awk -F'"' : "를 기준으로 분리
    # mapfile -t : 표준 입력을 배열로 저장
}

# Zone 조회
show_zone_list(){
    local -n _refzonearr=$1
    local _currentpage=${2:-0}
    local _maxzonecount=7 # 최대 표시할 zone 수
    local _zonetotal=${#_refzonearr[@]}

    local _start=$(( _currentpage * _maxzonecount ))
    local _end=$(( _start + _maxzonecount ))

    local _totalpages=$(( (_zonetotal - 1) / _maxzonecount ))

    echo "==============================================="
    echo "ZONE LIST"
    echo "==============================================="
    for (( i = _start; i < _end && i < _zonetotal; i++ )); do
        echo "$((i+1)). ${_refzonearr[i]}"
    done
    echo "==============================================="
    echo "PAGE : $((_currentpage+1)) / $((_totalpages+1)) | TOTAL ZONE COUNT : ${_zonetotal}"
    echo "==============================================="
}

# ZONE 파일 경로를 받아 Serial 갱신
update_serial() {
    local _zonefile=$1
    local _serial=$(awk '/serial/ {print $1}' "$_zonefile")
    local _newserial=$((_serial + 1))
    sed -i "s/${_serial}/${_newserial}/" "$_zonefile"
}