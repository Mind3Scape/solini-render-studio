# Компоненты и модели

Код Salini Render Studio — MIT. ZIP содержит собственный код и установщик; сторонние библиотеки, движок и веса скачиваются отдельно. Их лицензии находятся в пакетах или исходных репозиториях. Заявленный сценарий пользователя — некоммерческие исследования.

| Компонент / базовая модель | Источник | Лицензия |
|---|---|---|
| MFLUX 0.19.2 | https://github.com/mflux-community/mflux | MIT |
| Apple MLX | https://github.com/ml-explore/mlx | MIT |
| stable-diffusion.cpp / ggml | https://github.com/leejet/stable-diffusion.cpp | MIT; уведомления скачиваются с движком |
| FastAPI | https://github.com/fastapi/fastapi | MIT |
| Uvicorn | https://github.com/encode/uvicorn | BSD-3-Clause |
| Pillow | https://github.com/python-pillow/Pillow | MIT-CMU |
| NumPy | https://github.com/numpy/numpy | BSD-3-Clause |
| uv | https://github.com/astral-sh/uv | MIT / Apache-2.0 |
| FLUX.2 Klein 4B | https://huggingface.co/black-forest-labs/FLUX.2-klein-4B | Apache-2.0 |
| FLUX.2 Klein 9B KV | https://huggingface.co/black-forest-labs/FLUX.2-klein-9b-kv | FLUX Non-Commercial License |
| Qwen Image 2.1 | https://huggingface.co/Qwen/Qwen-Image-2.1 | Qwen Research License |
| Qwen Image Edit 2511 | https://huggingface.co/Qwen/Qwen-Image-Edit-2511 | Apache-2.0 |
| FireRed Image Edit 1.1 | https://huggingface.co/FireRedTeam/FireRed-Image-Edit-1.1 | Apache-2.0 |
| LongCat Image Edit | https://huggingface.co/meituan-longcat/LongCat-Image-Edit | Apache-2.0 |
| FIBO Edit 1.5 | https://huggingface.co/briaai/Fibo-Edit-1.5-base | BRIA FIBO Edit 1.5, некоммерческая |
| FLUX.2 dev | https://huggingface.co/black-forest-labs/FLUX.2-dev | FLUX Non-Commercial License |
| Real-ESRGAN x4plus | https://github.com/xinntao/Real-ESRGAN | BSD-3-Clause |

Дополнительные кодировщики: [Qwen3-VL-8B](https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF), [Qwen2.5-VL-7B](https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct), [Mistral Small 3.2](https://huggingface.co/mistralai/Mistral-Small-3.2-24B-Instruct-2506) — Apache-2.0. У VAE действуют условия соответствующих базовых моделей; LongCat использует VAE из собственного официального репозитория, Apache-2.0.

## Закреплённые сборки

MLX-кванты поставляются сообществом MFLUX: `mflux-community/flux2-klein-4b-mflux-q4`, `flux2-klein-9b-kv-mflux-q4`, `fibo-edit-1-5-base-mflux-q4`. GGUF-кванты — из репозиториев leejet, unsloth, vantagewithai, city96, mradermacher; VAE — Comfy-Org / Black Forest Labs; Qwen3-VL GGUF — Qwen. Это преобразования сторонних весов, не обучение и не собственные модели Salini.

Точные репозитории, имена файлов, размеры и неизменяемые ревизии всех компонентов указаны в `salini/catalog.py` и `salini/config.py`. Они также записываются в экспортируемые параметры обработки. Полные версии Python-зависимостей и контрольные суммы — в `uv.lock`.

Готовый движок Apple Silicon закреплён на выпуске [master-889-c678dfe](https://github.com/leejet/stable-diffusion.cpp/releases/tag/master-889-c678dfe). SHA-256 ZIP: `935f47067941d3fe095d80751f04c59cd8105e297177b98d559d9be1d9e7cfd8`. Лицензионные файлы `stable-diffusion.cpp.txt` и `ggml.txt` сохраняются рядом с бинарным файлом в папке данных.

Открытые веса не означают отсутствие условий использования. Лицензия кванта не отменяет условия базовой модели. Получатель программы должен учитывать лицензию выбранной модели. Проекты из справочного раздела каталога не входят в программу и не скачиваются.
