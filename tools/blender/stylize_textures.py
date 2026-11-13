"""Low-poly texture pass: flat, posterised colour instead of noisy painted detail.

Each texture is first shrunk to a coarse "shape" size (noise and grain vanish,
planks, tiles and patterns stay), smoothly enlarged to the output size, reduced
to a small k-means palette and cleaned with a 3x3 majority filter. The result is
clean flat areas with crisp edges, like the first-person props' labels.
Alpha is kept as is.

Originals are copied once to art_source/<same path> (ignored by Godot) and the
pass always starts from them, so it can be re-run with other settings:

    Blender -b --python tools/blender/stylize_textures.py
"""
import bpy, os, glob, shutil
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = os.path.join(ROOT, "art_source")

# Texture -> (palette size, output size, shape size). Small solid swatches are left alone.
PICTURES = {"house_0.png": (16, 384, 192), "house_1.png": (14, 384, 160), "house_9.png": (12, 384, 128)}
DEFAULT = (7, 256, 56)
MIN_SIZE = 96


def textures():
    return sorted(glob.glob(os.path.join(ROOT, "assets", "house_*.png")))


def original(path):
    rel = os.path.relpath(path, ROOT)
    keep = os.path.join(SOURCE, rel)
    if not os.path.exists(keep):
        os.makedirs(os.path.dirname(keep), exist_ok=True)
        shutil.copy2(path, keep)
    return keep


def kmeans(colors, k, rounds=14, seed=3):
    rng = np.random.default_rng(seed)
    sample = colors[rng.choice(len(colors), size=min(len(colors), 20000), replace=False)]
    # k-means++ style start: spread the first centres over the colour range.
    centers = [sample[rng.integers(len(sample))]]
    for _ in range(1, k):
        d = np.min(((sample[:, None, :] - np.array(centers)[None]) ** 2).sum(-1), axis=1).astype(np.float64)
        if d.sum() <= 1e-12:  # flat colour: nothing left to spread over
            centers.append(sample[rng.integers(len(sample))])
            continue
        centers.append(sample[rng.choice(len(sample), p=d / d.sum())])
    centers = np.array(centers)
    for _ in range(rounds):
        labels = np.argmin(((sample[:, None, :] - centers[None]) ** 2).sum(-1), axis=1)
        for c in range(k):
            members = sample[labels == c]
            if len(members):
                centers[c] = members.mean(0)
    return centers


def majority(labels, k):
    """Each pixel takes the most common palette index of its 3x3 neighbourhood (tiling)."""
    votes = np.zeros(labels.shape + (k,), dtype=np.int16)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            shifted = np.roll(np.roll(labels, dy, 0), dx, 1)
            np.put_along_axis(votes, shifted[..., None], np.take_along_axis(votes, shifted[..., None], 2) + 1, 2)
    return votes.argmax(2)


def stylize(path):
    name = os.path.basename(path)
    src = original(path)
    img = bpy.data.images.load(src)
    w, h = img.size
    if max(w, h) < MIN_SIZE:
        bpy.data.images.remove(img)
        return None
    k, limit, shape = PICTURES.get(name, DEFAULT)
    scale = min(1.0, limit / max(w, h))
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    coarse = min(1.0, shape / max(w, h))
    img.scale(max(1, round(w * coarse)), max(1, round(h * coarse)))
    img.scale(nw, nh)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    rgb = px[:, :3]
    centers = kmeans(rgb, k)
    labels = np.argmin(((rgb[:, None, :] - centers[None]) ** 2).sum(-1), axis=1).reshape(nh, nw)
    for _ in range(2):
        labels = majority(labels, k)
    px[:, :3] = centers[labels.ravel()]
    out = bpy.data.images.new(name + "_lp", nw, nh, alpha=True)
    out.pixels = px.ravel()
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(img)
    bpy.data.images.remove(out)
    return (w, h, nw, nh, k)


if __name__ == "__main__":
    os.makedirs(SOURCE, exist_ok=True)
    open(os.path.join(SOURCE, ".gdignore"), "w").close()
    for path in textures():
        done = stylize(path)
        if done:
            print("TEX %s %dx%d -> %dx%d, %d colours" % ((os.path.basename(path),) + done))
    print("TEXTURES done")
