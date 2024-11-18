#!/bin/bash

mkdir -p /data/prometheus/configuration
mkdir /data/prometheus/data
sudo chown 65534:65534 /data/prometheus/data
mkdir -p /data/grafana/data
mkdir /data/alertmanager

cat <<EOF> /data/docker-compose.yml

services:

  prometheus:
    image: prom/prometheus:latest
    volumes:
      - /data/prometheus/configuration:/etc/prometheus/
      - /data/prometheus/data:/prometheus/
    container_name: prometheus
    hostname: prometheus
    command:
      - --config.file=/etc/prometheus/prometheus.yml
    ports:
      - 9090:9090
    restart: unless-stopped
    environment:
      TZ: "Europe/Moscow"
    networks:
       default:
        ipv4_address: 10.10.10.31

  node-exporter:
    image: prom/node-exporter
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
      - /data:/datafs:ro
    container_name: exporter
    hostname: exporter
    command:
      - --path.procfs=/host/proc
      - --path.sysfs=/host/sys
      - --collector.filesystem.ignored-mount-points
      - ^/(sys|proc|dev|host|etc|rootfs/var/lib/docker/containers|rootfs/var/lib/docker/overlay2|rootfs/run/docker/netns|rootfs/var/lib/docker/aufs)($$|/)
    ports:
      - 9100:9100
    restart: unless-stopped
    environment:
      TZ: "Europe/Moscow"
    networks:
      default:
        ipv4_address: 10.10.10.13

  grafana:
    image: grafana/grafana-enterprise
    container_name: grafana
    restart: unless-stopped
    user: root
    depends_on:
      - prometheus
    networks:
      default:
        ipv4_address: 10.10.10.30

    environment:
    # - GF_SERVER_ROOT_URL=http://my.grafana.server/
     - GF_INSTALL_PLUGINS=grafana-clock-panel
    ports:
      - '3000:3000'
    volumes:
      - /data/grafana/data:/var/lib/grafana

  alertmanager-bot:
     command:
       - --alertmanager.url=http://10.10.10.33:9093
       - --log.level=info
       - --store=bolt
       - --bolt.path=/data/bot.db
       - --telegram.admin=1767793443
       - --telegram.token=5255213852:AAGsPkJAyLm9pTtKsAEzmNhkFSk6AimXtKk
     image: metalmatze/alertmanager-bot:0.4.3
     user: root
     ports:
       - 8080:8080
     container_name: alertmanager-bot
     hostname: alertmanager-bot
     environment:
       TZ: "Europe/Moscow"
     restart: unless-stopped
     volumes:
       - /data/alertmanager/data:/data
     networks:
      default:
        ipv4_address: 10.10.10.33

  alertmanager:
     image: prom/alertmanager:v0.21.0
     user: root
     ports:
       - 127.0.0.1:9093:9093
     volumes:
       - /data/alertmanager/:/etc/alertmanager/
     container_name: alertmanager
     hostname: alertmanager
     environment:
       TZ: "Europe/Moscow"
     restart: unless-stopped
     command:
       - '--config.file=/etc/alertmanager/config.yml'
       - '--storage.path=/etc/alertmanager/data'
     networks:
      default:
        ipv4_address: 10.10.10.32

networks:
    default:
     name: MyNet01
     driver: macvlan
     driver_opts:
       parent: enp6s18
     ipam:
       config:
        - subnet: 10.10.10.0/24
          ip_range: 10.10.10.170/29
          gateway: 10.10.10.1

EOF

cat <<EOF> /data/prometheus/configuration/prometheus.yml

global:
  scrape_interval: 10s

scrape_configs:
  - job_name: Linux-host
    static_configs:
     - targets:
        - 10.10.10.13:9100
        - 10.10.10.55:9100
        - 10.10.10.10:9100
        - 10.10.10.12:9100

  - job_name: win-server
    static_configs:
     - targets:
        - 10.10.10.44:9182

rule_files:
  - 'alert.rules'

alerting:
  alertmanagers:
  - scheme: http
    static_configs:
    - targets:
      - 10.10.10.33:9093

EOF

cat <<EOF> prometheus/configuration/alert.rules

groups: 
- name: test
  rules:
  - alert: Exporter-disable
    expr: up == 0
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Prometheus target missing (instance {{ $labels.instance }})"
      description: "A Prometheus target has disappeared. An exporter might be crashed. VALUE = {{ $value }}  LABELS: {{ $labels }}"

EOF

cat <<EOF> alertmanager/config.yml

route:
    receiver: 'alertmanager-bot'

receivers:
- name: 'alertmanager-bot'
  webhook_configs:
  - send_resolved: true
    url: 'http://10.10.10.33:8080'

EOF


docker-compose up -d