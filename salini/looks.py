"""Deterministic finishing controls; no generated pixels or geometry changes."""
import numpy as np
from PIL import Image

LOOKS = {
    'neutral': {'name': 'Нейтральный', 'description': 'Исходные цвета AI-результата.'},
    'warm': {'name': 'Тёплый', 'description': 'Медовый свет, тёплые белые поверхности и дерево.'},
    'cool': {'name': 'Холодный', 'description': 'Прохладные белые поверхности и чистые синие полутона.'},
    'vivid': {'name': 'Насыщенный', 'description': 'Более выразительные цвета и глубокие полутона.'},
    'soft': {'name': 'Мягкий', 'description': 'Светлые тени, приглушённые цвета, матовый вид.'},
    'contrast': {'name': 'Контрастный', 'description': 'Глубокие тени и более выраженный объём.'},
}


def apply_look(image, style='neutral', strength=60):
    if style not in LOOKS or not 0 <= strength <= 100:
        raise ValueError('Неизвестный цветовой вариант или неверная сила эффекта.')
    if style == 'neutral' or strength == 0:
        return image.copy()
    source = np.asarray(image.convert('RGB'), dtype=np.float32) / 255
    lum = source @ np.array([.2126, .7152, .0722], dtype=np.float32)
    gray = lum[..., None]
    if style == 'warm':
        effect = source * [1.10, 1.015, .84] + [.026, .008, 0]
    elif style == 'cool':
        effect = source * [.86, 1.015, 1.11] + [0, .006, .020]
    elif style == 'vivid':
        effect = ((gray + (source-gray)*1.65)-.5)*1.12 + .5
    elif style == 'soft':
        effect = ((gray + (source-gray)*.72)-.5)*.77 + .56
    else:
        effect = (source-.5)*1.40 + .5
    effect = np.clip(effect, 0, 1)
    result = source + (effect-source)*(strength/100)
    return Image.fromarray(np.rint(result*255).clip(0,255).astype(np.uint8))


def finish_image(before, generated, style='neutral', color_strength=60, amount=100, regions=()):
    from .imaging import restore_region
    if not 0 <= amount <= 100:
        raise ValueError('Сила обработки должна быть от 0 до 100%.')
    if amount == 0:
        return before.copy()
    toned = apply_look(generated, style, color_strength)
    output = Image.blend(before, toned, amount/100)
    for box in regions:
        output = restore_region(before, output, box)
    return output
