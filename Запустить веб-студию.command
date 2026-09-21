#!/bin/zsh
set -e
cd "$(dirname "$0")"
.venv/bin/python -m salini.online_host install
echo 'Нажмите Enter, чтобы закрыть окно. Служба продолжит работать.'
read
