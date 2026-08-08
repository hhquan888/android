#!/usr/bin/env python3
"""
Tao docker-compose.yml cho Redroid + ws-scrcpy.
Doc cac bien moi truong duoc set boi workflow truoc khi goi script nay.
"""
import os

image_tag     = os.environ['IMAGE_TAG']
ram_gb        = os.environ['RAM_GB']
cpu_limit     = os.environ['CPU_LIMIT']
abilist       = os.environ['ABILIST']
abilist64     = os.environ['ABILIST64']
abilist32     = os.environ['ABILIST32']
ndk           = os.environ.get('NDK_TRANSLATION', '')

# Dong NDK chi xuat hien neu chay tren host amd64
ndk_line = f'      - {ndk}\n' if ndk else ''

compose = f"""services:
  redroid:
    container_name: redroid
    image: {image_tag}
    privileged: true
    mem_limit: {ram_gb}g
    memswap_limit: {ram_gb}g
    cpus: "{cpu_limit}"
    ports:
      - "5555:5555"
    volumes:
      - ./data:/data
    environment:
      - REDROID_WIDTH=720
      - REDROID_HEIGHT=1280
      - REDROID_FPS=30
    command:
      - ro.product.cpu.abilist={abilist}
      - ro.product.cpu.abilist64={abilist64}
      - ro.product.cpu.abilist32={abilist32}
{ndk_line}    restart: unless-stopped

  custom-ws-scrcpy:
    container_name: custom-ws-scrcpy
    build:
      context: ./ws-scrcpy-build
      dockerfile: Dockerfile
    image: custom-ws-scrcpy:latest
    privileged: true
    ports:
      - "8000:8000"
    depends_on:
      - redroid
    restart: unless-stopped
    entrypoint:
      - sh
      - -c
      - >-
        adb start-server &&
        for i in $(seq 1 30); do
          adb connect redroid:5555 | grep -q connected && break;
          echo "retry $i..."; sleep 5;
        done &&
        ( while true; do
            sleep 10;
            adb devices | grep -q 'redroid:5555.*device' || adb connect redroid:5555;
          done ) &
        npm start
"""

with open('docker-compose.yml', 'w') as f:
    f.write(compose)

print(f'docker-compose.yml written')
print(f'  image:   {image_tag}')
print(f'  ram:     {ram_gb}g')
print(f'  cpu:     {cpu_limit}')
print(f'  abi:     {abilist}')
print(f'  ndk:     {ndk or "(none)"}')
