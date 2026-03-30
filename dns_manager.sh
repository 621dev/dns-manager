#!/bin/bash
# ============================================================
# install_named() : BIND 설치 (dns_crud.sh)
# delete_named()  : BIND 삭제 (dns_crud.sh)
# manage_zone()   : Zone 관리 메뉴 진입 (zone_manager.sh)
# ============================================================
clear

# 로그 파일 (있으면 가져오고, 없으면 생성)
# dirname : 파일의 경로만 가져옴
# realpath : 파일 경로의 실제 절대 경로로 변환
# $0 : 스크립트의 호출 경로를 의미
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
LOG_FILE="$SCRIPT_DIR/dns_manager.log"  # 로그파일 경로, 이 스크립트에서 함수가 호출된 모든 스크립트가 사용이 가능하다. 
DNS_IP=$(hostname -I | awk '{print $1}')  # 여러 개의 ip 주소가 할당되있을 경우를 고려하여 첫번째 IP만 가져옴

source "$SCRIPT_DIR/dns_crud.sh"
source "$SCRIPT_DIR/zone_manager.sh"
source "$SCRIPT_DIR/dns_setting.sh"

if [ ! -f "$LOG_FILE" ]; then   # -f : 파일이 존재하고 일반 파일인지 확인하는 Bash 내장 명령어, exit code 0이 참
    # 로그 파일이 없으면 빈 텍스트 파일을 새로 만듭니다.
    touch "$LOG_FILE"
    echo "$(date '+%Y%m%d %H%M%S') - DNS 매니저 로그 파일 생성됨" > "$LOG_FILE"
fi

# 메인 메뉴
while : 
do
    BIND_VERSION=$(rpm -qa bind)
    echo "==============================================="
    if [ -n "$BIND_VERSION" ]; then   # -n : 문자열의 길이가 0보다 크면 참
        echo "DNS 서비스 설치됨 ($BIND_VERSION)"
    else
        echo "DNS 서비스 미설치"
    fi
    echo "==============================================="
    echo "1. DNS 서비스 설치"
    echo "2. DNS 삭제"
    echo "3. DNS 설정"
    echo "4. Zone 관리"
    echo "5. 방화벽 포트 관리 (미구현)"
    echo "q. 종료" 
    echo "==============================================="
    read -p "원하는 작업을 선택하세요: " INPUT
    if [ "$INPUT" == "q" ]; then exit 0; fi
    if [ -n "$BIND_VERSION" ]; then     # DNS 서버 설치
        case $INPUT in
            1)
                echo "DNS 서비스가 설치 되어있습니다. 삭제 후 다시 시도해주세요."
                ;;
            2)
                delete_named    # named 서비스 삭제 함수
                ;;
            3)  
                set_dns
                ;;
            4)
                manage_zone
                ;;
            *)
                echo "잘못된 입력입니다. 다시 시도해주세요."
                ;;
        esac
    else    # DNS 서버 미설치
        case $INPUT in
            1)
                install_named
                ;;
            2|3|4)
                echo "DNS 서비스를 설치해주세요"
                ;;
            5)
                echo "미구현 항목입니다."
                ;;
            *)
                echo "잘못된 입력입니다. 다시 시도해주세요."
                ;;
        esac
    fi
done



# 슬레이브 변경
# 존 파일 수정 (refresh, retry, expire, minimum)
# 환경설정 - named.conf 설정, listen-on port v6, allow-query, 슬레이브 서버 지정
# named.conf : listen-on, allow-query 수정
# Slave 서버 rfc1912.zones 수정
# 자동으로 추가할 순 없을까?
# 안되면 정방향 도메인 연속입력, 역방향 네트워크 연속입력으로 처리
# 슬레이브 서버 지정
# ip를 입력한 후 zone 파일 리스트를 보여주고 연속으로 입력하면 (숫자로도 가능) 자동으로 기본값으로 추가하는 형식
