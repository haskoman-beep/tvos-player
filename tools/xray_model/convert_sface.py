#!/usr/bin/env python3
"""Download SFace (OpenCV Zoo, Apache-2.0) and convert it to a Core ML fp16 ML program.

Runs in CI only (GitHub Actions, macOS; see .github/workflows/build.yml, step "Face model (SFace)").
The model is never committed: the result App/Resources/SFace.mlpackage is generated here and Xcode
compiles it to SFace.mlmodelc inside Player.app.

Steps:
  1. Download face_recognition_sface_2021dec.onnx at a pinned opencv_zoo commit and verify its size and
     SHA-256 (the Git LFS oid of that file; the Hugging Face mirror publishes the same oid).
  2. Inspect the ONNX graph: input/output names and shapes, and any normalisation ops (Sub/Mul/Div/Add with
     constants) in front of the first convolution. Logged as "xray-model: ..." lines.
  3. ONNX -> PyTorch (onnx2torch) -> torch.jit.trace -> coremltools ML program, fp16, tvOS 18,
     input "data" 1x3x112x112 float32, output "embedding" 1x128 float32.
  4. Sanity check: fixed synthetic 112x112 inputs (values 0..255) through ONNX Runtime (fp32) and Core ML
     (fp16, CPU only and all compute units). Every cosine must be >= 0.999, otherwise the script fails.

Usage: python3 tools/xray_model/convert_sface.py --out App/Resources/SFace.mlpackage --work <tmp dir>
       python3 tools/xray_model/convert_sface.py --print-sha   (prints the pinned SHA-256, for the cache key)
"""

import argparse
import hashlib
import http.client
import json
import os
import sys
import time
import urllib.request

# Pinned source. COMMIT is an opencv_zoo commit that contains the file (the file itself last changed in
# ba91a3b91d00d76e86540d4013f944bd6b514e39, "update sface: quantization ready (#35)", 2022-01-06).
ZOO_COMMIT = "48b10fa505aeb51fbd127fc60a5c660040e823b7"
ZOO_PATH = "models/face_recognition_sface/face_recognition_sface_2021dec.onnx"
# SHA-256 = Git LFS oid from the pointer file at ZOO_COMMIT (same oid on the Hugging Face mirror
# opencv/face_recognition_sface). Empty string: the script prints the hash of the download and fails.
ONNX_SHA256 = "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"
ONNX_SIZE = 38696353
URLS = [
    f"https://media.githubusercontent.com/media/opencv/opencv_zoo/{ZOO_COMMIT}/{ZOO_PATH}",
    # Mirror (same LFS object), pinned to a Hugging Face commit.
    "https://huggingface.co/opencv/face_recognition_sface/resolve/"
    "3d7082438a6e4551e840c9b2bb60b71e8da4b524/face_recognition_sface_2021dec.onnx",
]

INPUT_NAME = "data"
OUTPUT_NAME = "embedding"
SIDE = 112
DIM = 128
MIN_COSINE = 0.999


def log(msg):
    print(f"xray-model: {msg}", flush=True)


def fail(msg):
    print(f"::error title=SFace::{msg}", flush=True)
    sys.exit(1)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(work):
    dest = os.path.join(work, "face_recognition_sface_2021dec.onnx")
    last_err = None
    for url in URLS:
        for attempt in range(3):
            try:
                log(f"download {url} (attempt {attempt + 1})")
                req = urllib.request.Request(url, headers={"User-Agent": "player-ci-model-fetch"})
                with urllib.request.urlopen(req, timeout=120) as r, open(dest + ".part", "wb") as f:
                    while True:
                        chunk = r.read(1 << 20)
                        if not chunk:
                            break
                        f.write(chunk)
                os.replace(dest + ".part", dest)
                size = os.path.getsize(dest)
                digest = sha256_of(dest)
                log(f"downloaded {size} bytes, sha256 {digest}")
                if not ONNX_SHA256:
                    fail(f"no pinned SHA-256: set ONNX_SHA256 = \"{digest}\" in convert_sface.py after checking it")
                if digest != ONNX_SHA256 or size != ONNX_SIZE:
                    # For example an LFS pointer or an error page with status 200: try the next source.
                    last_err = f"hash/size mismatch: got {digest} / {size}, expected {ONNX_SHA256} / {ONNX_SIZE}"
                    log(last_err)
                    os.remove(dest)
                    break
                log("sha256 verified")
                return dest
            except (OSError, urllib.error.URLError, http.client.HTTPException) as e:
                last_err = e
                log(f"download failed: {e}")
                time.sleep(5)
    fail(f"download failed from all sources: {last_err}")


def const_value(name, inits, consts):
    import numpy as np
    from onnx import numpy_helper

    if name in inits:
        return numpy_helper.to_array(inits[name])
    if name in consts:
        return consts[name]
    return None


def inspect_graph(onnx_path):
    """Log the graph interface and every op between the input and the first Conv."""
    import numpy as np
    import onnx
    from onnx import numpy_helper

    model = onnx.load(onnx_path)
    g = model.graph
    inits = {i.name: i for i in g.initializer}
    real_inputs = [i for i in g.input if i.name not in inits]

    def dims(vi):
        return [d.dim_value if d.dim_value else (d.dim_param or "?") for d in vi.type.tensor_type.shape.dim]

    log(f"onnx opset {[ (o.domain or 'ai.onnx', o.version) for o in model.opset_import ]}, "
        f"producer {model.producer_name} {model.producer_version}, nodes {len(g.node)}")
    for i in real_inputs:
        log(f"onnx input  {i.name} {dims(i)}")
    for o in g.output:
        log(f"onnx output {o.name} {dims(o)}")

    consts = {}
    for n in g.node:
        if n.op_type == "Constant":
            for a in n.attribute:
                if a.name == "value":
                    consts[n.output[0]] = numpy_helper.to_array(a.t)

    # Walk forward from the graph input until the first Conv.
    frontier = {i.name for i in real_inputs}
    head, first_conv = [], None
    for n in g.node:
        if n.op_type == "Constant":
            continue
        if not any(x in frontier for x in n.input):
            continue
        if n.op_type == "Conv":
            first_conv = n
            break
        operands = []
        for x in n.input:
            if x in frontier:
                operands.append("<x>")
            else:
                v = const_value(x, inits, consts)
                operands.append(repr(np.asarray(v).ravel()[:4].tolist()) if v is not None else x)
        head.append(f"{n.op_type}({', '.join(operands)})")
        frontier.update(n.output)

    if head:
        log("ops before the first Conv: " + " -> ".join(head))
    else:
        log("ops before the first Conv: none (the graph applies no channel swap, mean or scale)")
    if first_conv is not None:
        w = const_value(first_conv.input[1], inits, consts)
        after = [n.op_type for n in g.node if first_conv.output[0] in n.input]
        log(f"first Conv weight {list(w.shape) if w is not None else '?'}, "
            f"has bias {len(first_conv.input) > 2}, followed by {after}")
        if w is not None:
            # Weight sum per input channel: if the three columns are near-identical the net is roughly
            # colour-order agnostic at layer 1; strongly different sums show it cares about the order.
            per_c = np.asarray(w, dtype=np.float64).sum(axis=(0, 2, 3))
            log(f"first Conv weight sum per input channel (c0, c1, c2): {np.round(per_c, 4).tolist()}")
    return model, head, [i.name for i in real_inputs], [o.name for o in g.output]


def synthetic_inputs():
    """Fixed, reproducible 112x112 test pictures, planar NCHW float32."""
    import numpy as np

    rng = np.random.RandomState(20261122)
    noise = rng.uniform(0.0, 255.0, size=(1, 3, SIDE, SIDE)).astype(np.float32)
    yy, xx = np.mgrid[0:SIDE, 0:SIDE].astype(np.float32) / (SIDE - 1)
    smooth = np.stack([
        127.5 + 100.0 * np.sin(2.0 * np.pi * (1.5 * xx + 0.5 * yy)),
        127.5 + 90.0 * np.cos(2.0 * np.pi * (0.7 * xx - 1.2 * yy)),
        255.0 * (0.25 + 0.5 * xx * yy),
    ])[None].astype(np.float32)
    # A face-like blob: bright oval, two dark eyes, a dark mouth, on a mid-grey background.
    blob = np.full((SIDE, SIDE), 90.0, dtype=np.float32)
    oval = ((xx - 0.5) / 0.32) ** 2 + ((yy - 0.52) / 0.42) ** 2 <= 1.0
    blob[oval] = 200.0
    for cx in (0.36, 0.64):
        blob[((xx - cx) / 0.06) ** 2 + ((yy - 0.42) / 0.035) ** 2 <= 1.0] = 40.0
    blob[((xx - 0.5) / 0.13) ** 2 + ((yy - 0.76) / 0.03) ** 2 <= 1.0] = 60.0
    face = np.stack([blob, blob * 0.85, blob * 0.7])[None].astype(np.float32)
    # (name, input, gated). The graph normalises internally ((x - 127.5) * 0.0078125), so the real input range
    # is 0..255. "faceblob_prenorm" feeds an already normalised picture (normalised twice, far outside the
    # trained range); it is logged for information only and does not count for the cosine threshold.
    cases = [("noise_0_255", noise, True), ("smooth_0_255", smooth, True), ("faceblob_0_255", face, True),
             ("faceblob_prenorm", (face - 127.5) / 128.0, False)]
    return cases


def cosine(a, b):
    import numpy as np

    a = np.asarray(a, dtype=np.float64).ravel()
    b = np.asarray(b, dtype=np.float64).ravel()
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12))


def convert(onnx_model, out_path):
    import numpy as np
    import torch
    import coremltools as ct
    from onnx2torch import convert as onnx_to_torch

    torch_model = onnx_to_torch(onnx_model).eval()
    example = torch.zeros(1, 3, SIDE, SIDE, dtype=torch.float32)
    with torch.no_grad():
        traced = torch.jit.trace(torch_model, example)
    mlmodel = ct.convert(
        traced,
        source="pytorch",
        inputs=[ct.TensorType(name=INPUT_NAME, shape=(1, 3, SIDE, SIDE), dtype=np.float32)],
        outputs=[ct.TensorType(name=OUTPUT_NAME, dtype=np.float32)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.tvOS18,
    )
    mlmodel.short_description = (
        "SFace face embedding (OpenCV Zoo face_recognition_sface_2021dec), 128-d, fp16. "
        "Input: aligned 112x112 face, planar RGB float32 NCHW, 0..255; see THIRD_PARTY_NOTICES.md."
    )
    mlmodel.author = "SFace: Zhong et al.; ONNX model: OpenCV Zoo"
    mlmodel.license = "Apache-2.0"
    mlmodel.version = "2021dec"
    mlmodel.input_description[INPUT_NAME] = "1x3x112x112 aligned face, planar RGB, values 0..255 (normalised inside the model)"
    mlmodel.output_description[OUTPUT_NAME] = "1x128 embedding, not normalised (L2-normalise before cosine)"
    if os.path.exists(out_path):
        fail(f"{out_path} already exists - remove it first")
    mlmodel.save(out_path)
    log(f"saved {out_path}")
    return torch_model, mlmodel


def sanity(onnx_path, onnx_input, onnx_output, torch_model, out_path):
    import numpy as np
    import torch
    import onnxruntime as ort
    import coremltools as ct

    sess = ort.InferenceSession(onnx_path, providers=["CPUExecutionProvider"])
    ml_cpu = ct.models.MLModel(out_path, compute_units=ct.ComputeUnit.CPU_ONLY)
    try:
        ml_all = ct.models.MLModel(out_path, compute_units=ct.ComputeUnit.ALL)
    except Exception as e:  # noqa: BLE001 - only logged, CPU result is the hard check
        log(f"compute units ALL unavailable: {e}")
        ml_all = None

    worst = 1.0
    refs = {}
    for name, x, gated in synthetic_inputs():
        ref = sess.run([onnx_output], {onnx_input: x})[0]
        if ref.shape[-1] != DIM:
            fail(f"ONNX output has shape {ref.shape}, expected (1, {DIM})")
        with torch.no_grad():
            tout = torch_model(torch.from_numpy(x)).numpy()
        cpu = ml_cpu.predict({INPUT_NAME: x})[OUTPUT_NAME]
        if np.asarray(cpu).size != DIM:
            fail(f"Core ML output has {np.asarray(cpu).size} values, expected {DIM}")
        c_torch, c_cpu = cosine(ref, tout), cosine(ref, cpu)
        line = f"sanity {name}: cos(onnx fp32, torch) {c_torch:.6f} · cos(onnx fp32, coreml fp16 cpu) {c_cpu:.6f}"
        if gated:
            worst = min(worst, c_torch, c_cpu)
        else:
            line = "(info only) " + line
        if ml_all is not None:
            try:
                allu = ml_all.predict({INPUT_NAME: x})[OUTPUT_NAME]
                c_all = cosine(ref, allu)
                line += f" · cos(onnx fp32, coreml fp16 all) {c_all:.6f}"
                if gated:
                    worst = min(worst, c_all)
            except Exception as e:  # noqa: BLE001
                line += f" · coreml all failed: {e}"
        line += f" · |onnx| {np.linalg.norm(ref):.3f} · onnx[0:4] {np.round(ref.ravel()[:4], 4).tolist()}"
        log(line)
        refs[name] = ref.ravel()
    # Distinct inputs must give distinct embeddings (guards against a constant/degenerate output).
    names = list(refs)
    pair = cosine(refs[names[0]], refs[names[2]])
    log(f"sanity distinctness: cos({names[0]}, {names[2]}) {pair:.4f} (must be < 0.99)")
    if pair >= 0.99:
        fail("embeddings of different inputs are nearly identical - model output looks degenerate")
    log(f"sanity worst cosine over the 0..255 inputs {worst:.6f} (required >= {MIN_COSINE})")
    if worst < MIN_COSINE:
        fail(f"Core ML fp16 does not match ONNX fp32: worst cosine {worst:.6f} < {MIN_COSINE}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="App/Resources/SFace.mlpackage")
    ap.add_argument("--work", default=None, help="directory for the download (default: $RUNNER_TEMP)")
    ap.add_argument("--print-sha", action="store_true")
    args = ap.parse_args()
    if args.print_sha:
        print(ONNX_SHA256)
        return
    work = args.work or os.environ.get("RUNNER_TEMP")
    if not work:
        fail("--work or RUNNER_TEMP is required")
    os.makedirs(work, exist_ok=True)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)

    onnx_path = download(work)
    onnx_model, head, inputs, outputs = inspect_graph(onnx_path)
    if len(inputs) != 1 or len(outputs) != 1:
        fail(f"expected one input and one output, got {inputs} / {outputs}")
    # Reference preprocessing in OpenCV (modules/objdetect/src/face_recognize.cpp, FaceRecognizerSF::feature):
    #   blobFromImage(aligned_bgr, scalefactor=1, size=112x112, mean=0, swapRB=true, crop=false)
    log("reference preprocessing (OpenCV FaceRecognizerSF::feature): blobFromImage(scale 1, mean 0, swapRB true) "
        "on the BGR aligned crop -> the network is fed RGB, 0..255, no mean, no scale")
    normalising = [h for h in head if h.split("(")[0] in ("Sub", "Mul", "Div", "Add")]
    if head:
        log(f"graph-internal preprocessing found: {' -> '.join(head)}")
    if head and len(normalising) == len(head):
        log("RESULT input format: planar RGB, values 0..255 (FaceInputFormat .raw); the graph itself applies "
            f"{' -> '.join(head)}, so do not normalise in Swift")
    elif not head:
        log("RESULT input format: planar RGB, values 0..255 (FaceInputFormat .raw); no normalisation in the graph")
    else:
        log("RESULT input format: unclear, the graph starts with other ops - check the lines above")
    torch_model, _ = convert(onnx_model, args.out)
    sanity(onnx_path, inputs[0], outputs[0], torch_model, args.out)
    size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(args.out) for f in fs)
    log(f"done: {args.out} ({size / 1e6:.1f} MB)")
    with open(os.path.join(work, "sface_convert_summary.json"), "w") as f:
        json.dump({"graph_head": head, "input": inputs[0], "output": outputs[0], "mlpackage_bytes": size}, f)


if __name__ == "__main__":
    main()
