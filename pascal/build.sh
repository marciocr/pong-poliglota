#!/usr/bin/env bash
# Compila o Pong em Object Pascal com o Free Pascal Compiler.
# Uso: ./build.sh          -> gera build/pong
#      ./build.sh clean    -> remove build/
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" == "clean" ]]; then
  rm -rf build
  exit 0
fi

mkdir -p build
fpc -O2 -Xs -vew -FUbuild -obuild/pong pong.pas
echo "ok: build/pong"
