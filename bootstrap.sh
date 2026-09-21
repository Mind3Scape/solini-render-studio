#!/bin/zsh
# Reproducible bootstrap. Does not require Homebrew, Xcode, Python or Codex.
set -eu
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo 'Нужен Mac с чипом Apple M1 или новее (не Intel/Rosetta).'
  exit 1
fi
mkdir -p .tools
if [[ ! -x .tools/salini-uv ]]; then
  echo 'Загрузка установщика Python…'
  archive="$(mktemp -t salini-uv)"
  trap 'rm -f "$archive"' EXIT
  /usr/bin/curl --fail --location --retry 3 --output "$archive" 'https://files.pythonhosted.org/packages/3d/1f/b617a27538bf631e488e2918f02dc22c210ce095baa01e50a3f85cf29621/uv-0.12.17-py3-none-macosx_11_0_arm64.whl'
  expected='c33d2fb4fb407678e2da3907376e7f5a7a38ae11e53d608bb7be70c1ecb6f223'
  actual="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo 'Ошибка проверки загруженного установщика. Повторите установку.'
    exit 1
  fi
  /usr/bin/unzip -p "$archive" 'uv-0.12.17.data/scripts/uv' > .tools/salini-uv.part
  chmod 755 .tools/salini-uv.part
  mv .tools/salini-uv.part .tools/salini-uv
fi
echo 'Установка Salini Render Studio. При первом запуске это может занять несколько минут…'
.tools/salini-uv sync --frozen --no-dev --python 3.12 --managed-python
echo 'Готово. Модель загрузится при первой обработке изображения.'
