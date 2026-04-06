FROM rockylinux:9

# BIND 및 필요 패키지 설치
RUN dnf install -y \
    bind \
    bind-utils \
    iproute \
    procps-ng \
    util-linux \
    && dnf clean all

# 스크립트 복사
WORKDIR /opt/dns-manager
COPY dns_manager_docker.sh .
COPY dns_crud_docker.sh .
COPY dns_setting_docker.sh .
COPY zone_manager_docker.sh .
COPY zone_crud_docker.sh .

RUN chmod +x *.sh

# named 설정 디렉토리
VOLUME ["/etc/named", "/var/named", "/opt/dns-manager/data"]

EXPOSE 53/tcp
EXPOSE 53/udp

CMD ["/bin/bash", "/opt/dns-manager/dns_manager_docker.sh"]
