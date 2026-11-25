"""Reference model of the 28-position layout, used to prove sphere coverage before the Swift code relies on it.
The Swift SphereLayout.swift implements exactly these formulas."""
import numpy as np

def targets(h_fov, v_fov, overlap=0.2):
    """Returns list of (name, azimuth_deg, elevation_deg). Camera held in LANDSCAPE: image width spans h_fov."""
    e1 = v_fov * (1 - overlap)                          # upper / lower ring elevation: rows overlap by `overlap` of v_fov
    t = [("zenith", 0.0, 90.0)]
    t += [(f"up{k}", 45.0 * k + 22.5, e1) for k in range(8)]
    t += [(f"mid{k}", 45.0 * k, 0.0) for k in range(8)]
    t += [(f"low{k}", 45.0 * k + 22.5, -e1) for k in range(8)]
    return t

def frame(az, el):
    az, el = np.radians(az), np.radians(el)
    f = np.array([np.sin(az) * np.cos(el), np.sin(el), np.cos(az) * np.cos(el)])     # y UP here
    up0 = np.array([0, 1.0, 0])
    if abs(f[1]) > 0.999:                                # looking straight up/down: roll reference = azimuth direction
        right = np.array([np.cos(az), 0, -np.sin(az)])
    else:
        right = np.cross(up0, f); right /= np.linalg.norm(right)
    up = np.cross(f, right)
    return right, up, f

def covered(dirs, az, el, h_fov, v_fov, shrink=1.0):
    r, u, f = frame(az, el)
    z = dirs @ f
    with np.errstate(divide="ignore", invalid="ignore"):
        x, y = (dirs @ r) / z, (dirs @ u) / z
    return (z > 0) & (np.abs(x) < np.tan(np.radians(h_fov / 2)) * shrink) & (np.abs(y) < np.tan(np.radians(v_fov / 2)) * shrink)

def sphere_samples(n=300000, seed=0):
    rng = np.random.default_rng(seed)
    d = rng.standard_normal((n, 3)); return d / np.linalg.norm(d, axis=1, keepdims=True)

def report(name, tg, h, v, dirs):
    cnt = np.zeros(len(dirs), int)
    for _, az, el in tg:
        cnt += covered(dirs, az, el, h, v)
    # usable overlap: pixels well inside at least one frame (80% of the frame) AND covered at least once
    core = np.zeros(len(dirs), bool)
    for _, az, el in tg:
        core |= covered(dirs, az, el, h, v, shrink=0.8)
    print(f"{name}: covered {100 * (cnt >= 1).mean():.2f}%  (>=2 frames: {100 * (cnt >= 2).mean():.1f}%, "
          f"inside the 80% core of some frame: {100 * core.mean():.2f}%)  uncovered samples: {int((cnt == 0).sum())}")
    return cnt

if __name__ == "__main__":
    dirs = sphere_samples()
    H, V = 67.4, 53.0                       # iPhone main camera, 4:3 photo, device held in landscape
    base = targets(H, V)
    print(f"e1 (ring elevation) = {V * 0.8:.1f} deg; 25 positions without nadir/supplementals")
    cnt = report("25 positions       ", base, H, V, dirs)
    s1 = base + [("nadir", 0.0, -90.0)]
    cnt = report("26 (+nadir)        ", s1, H, V, dirs)
    # greedy choice of the 2 remaining supplementals: candidates on a grid, maximise newly covered samples
    cands = [(az, el) for el in range(-80, 81, 10) for az in range(0, 360, 15)]
    cur = cnt.copy(); chosen = []
    for _ in range(2):
        best = max(cands, key=lambda c: ((cur == 0) & covered(dirs, c[0], c[1], H, V)).sum() * 1000 + ((cur == 1) & covered(dirs, c[0], c[1], H, V)).sum())
        chosen.append(best); cur += covered(dirs, best[0], best[1], H, V)
    print("greedy supplementals:", chosen, "-> uncovered after:", int((cur == 0).sum()))
