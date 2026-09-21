#!/bin/zsh
set -e
cd "$(dirname "$0")"
if [[ ! -x .venv/bin/python ]]; then
  /bin/zsh bootstrap.sh || { echo 'Установка не завершена. Нажмите Enter, чтобы закрыть окно.'; read; exit 1; }
fi
.venv/bin/python -m salini.launcher || { echo 'Не удалось запустить приложение. Нажмите Enter.'; read; exit 1; }
