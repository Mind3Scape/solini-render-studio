#!/bin/zsh
set -e
cd "$(dirname "$0")"
/bin/zsh bootstrap.sh || { echo 'Установка не завершена. Нажмите Enter.'; read; exit 1; }
.venv/bin/python -m salini.launcher
