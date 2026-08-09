#!/usr/bin/env python3
"""
Tao docker-compose.yml cho Redroid (image chinh chu redroid/redroid, Android 12)
+ ws-scrcpy. Doc bien moi truong duoc set boi workflow truoc khi goi script nay.
"""
import os

image_tag = os.environ['IMAGE_TAG']
ram_gb    = os.environ['RAM_GB']
cpu_limit = os.environ['CPU_LIMIT']
abilist   = os.environ['ABILIST']
abilist64 = os.environ['ABILIST64']
abilist32 = os.environ['ABILIST32']
ndk       = os.environ.get('NDK_TRANSLATION', '')

ndk_line = f'      - {ndk}\n' if ndk else ''

# QUAN TRONG: entrypoint dung bien shell $i, $(...). docker-compose tu lam
# bien the ${VAR} truoc khi Docker thay - phai escape thanh $$ de tranh loi
# "The 'i' variable is not set".
entrypoint_script = (
    "adb start-server && "
    "for i in $$(seq 1 30); do "
    "adb connect redroid:5555 | grep -q connected && break; "
    "echo retry $$i...; sleep 5; "
    "done && "
    "( while true; do "
    "sleep 10; "
    "adb devices | grep -q 'redroid:5555.*device' || adb connect redroid:5555; "
    "done ) & "
    "npm start"
)

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
    command:
      - androidboot.redroid_width=720
      - androidboot.redroid_height=1280
      - androidboot.redroid_fps=30
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
    pull_policy: build
    privileged: true
    ports:
      - "8000:8000"
    depends_on:
      - redroid
    restart: unless-stopped
    entrypoint:
      - sh
      - -c
      - "{entrypoint_script}"
"""

with open('docker-compose.yml', 'w') as f:
    f.write(compose)

print(f'docker-compose.yml written')
print(f'  image: {image_tag}')
print(f'  ram:   {ram_gb}g')
print(f'  cpu:   {cpu_limit}')
print(f'  abi:   {abilist}')
print(f'  ndk:   {ndk or "(none)"}')
