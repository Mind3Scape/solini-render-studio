"""Pin a generated ambient loop to its real intro endpoint.

Kling start/end anchors still have small texture/exposure residuals. A smooth
YUV residual correction removes that drift over the entire generated clip;
it does not warp geometry, reverse motion, or dissolve between still images.
The duplicated endpoint is omitted, yielding 96 distinct frames at 24 fps.
Use only for visually matched, locked-camera source clips. Review the output.

python3 finish_loop.py intro.mp4 generated-loop.mp4 finished-loop.mp4
"""
import json
import subprocess
import sys
import numpy as np


def info(path):
    data = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-show_streams', '-of', 'json', path]))
    return next(t for t in data['streams'] if t['codec_type'] == 'video')


intro_path, source_path, output_path = sys.argv[1:]
meta = info(source_path)
w, h = meta['width'], meta['height']
# Keep the source YUV range and matrix untouched. An RGB round trip can add
# a small brightness step even when the two boundary images look identical.
assert meta['pix_fmt'] == 'yuv420p'
shape = (w*h*3//2,)
frame_bytes = w*h*3//2
rate = meta['avg_frame_rate']
assert (info(intro_path)['width'], info(intro_path)['height']) == (w, h)


def frame(path, last=False):
    args = ['ffmpeg', '-v', 'error']
    if last:
        args += ['-sseof', '-0.042']
    args += ['-i', path, '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'yuv420p', '-']
    return np.frombuffer(subprocess.check_output(args), np.uint8).reshape(shape).astype(np.float32)


anchor = frame(intro_path, True)
first, last = frame(source_path), frame(source_path, True)
head_residual, tail_residual = anchor-first, anchor-last
count = int(meta['nb_frames'])
print(json.dumps(dict(source_frames=count, output_frames=count-1,
                      head_residual_mae=float(np.abs(head_residual).mean()),
                      tail_residual_mae=float(np.abs(tail_residual).mean()))), flush=True)
decoder = subprocess.Popen(['ffmpeg', '-v', 'error', '-i', source_path,
                            '-f', 'rawvideo', '-pix_fmt', 'yuv420p', '-'], stdout=subprocess.PIPE)
encoder = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo',
                            '-pixel_format', 'yuv420p', '-video_size', f'{w}x{h}',
                            '-framerate', rate, '-i', '-', '-an', '-c:v', 'libx264',
                            '-preset', 'slow', '-crf', '18', '-pix_fmt', 'yuv420p',
                            '-g', '24', '-flags', '+cgop',
                            '-movflags', '+faststart', output_path], stdin=subprocess.PIPE)
try:
    for i in range(count):
        raw = decoder.stdout.read(frame_bytes)
        if len(raw) != frame_bytes:
            raise RuntimeError(f'Incomplete source frame {i}')
        if i == count-1:
            continue
        pixels = np.frombuffer(raw, np.uint8).reshape(shape).astype(np.float32)
        t = i/(count-1)
        smooth = t*t*(3-2*t)
        pixels += head_residual*(1-smooth) + tail_residual*smooth
        encoder.stdin.write(np.clip(np.rint(pixels), 0, 255).astype(np.uint8).tobytes())
finally:
    decoder.stdout.close()
    encoder.stdin.close()
assert decoder.wait() == 0
assert encoder.wait() == 0
