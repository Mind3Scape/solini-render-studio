"""Decode delivered films; report movement and seams without altering footage.

Run: python3 check_motion.py intro.mp4 loop.mp4
Numbers complement visual review; they do not prove perceptual seamlessness.
"""
import json
import subprocess
import sys
import numpy as np


def decode(path):
    metadata = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", path
    ]))
    track = next(t for t in metadata["streams"] if t["codec_type"] == "video")
    height = round(256 * track["height"] / track["width"])
    pixels = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path, "-vf", f"scale=256:{height}",
        "-pix_fmt", "gray", "-f", "rawvideo", "-"
    ])
    frames = np.frombuffer(pixels, dtype=np.uint8).reshape(-1, height, 256).astype(np.float32)
    return frames, dict(width=track["width"], height=track["height"],
                       fps=track["avg_frame_rate"], frames=len(frames),
                       duration=float(metadata["format"]["duration"]),
                       audio=any(t["codec_type"] == "audio" for t in metadata["streams"]))


intro, intro_info = decode(sys.argv[1])
loop, loop_info = decode(sys.argv[2])
steps = np.abs(np.diff(loop, axis=0)).mean(axis=(1, 2))
seam = float(np.abs(loop[-1] - loop[0]).mean())
join = float(np.abs(intro[-1] - loop[0]).mean())
print(json.dumps(dict(intro=intro_info, loop=loop_info,
                     luma_mad_0_255=dict(intro_to_loop=join, loop_seam=seam,
                                       median_step=float(np.median(steps)),
                                       p95_step=float(np.percentile(steps, 95)),
                                       max_step=float(steps.max()),
                                       first_to_middle=float(np.abs(loop[len(loop)//2]-loop[0]).mean())),
                     duplicate_adjacent_frames=int((steps == 0).sum())), indent=2))
