import torch, numpy as np, coremltools as ct, time, sys
from quran_muaalem.modeling.modeling_multi_level_ctc import Wav2Vec2BertForMultilevelCTC
torch.set_grad_enabled(False)
from coremltools.converters.mil.frontend.torch.torch_op_registry import register_torch_op
from coremltools.converters.mil.frontend.torch.ops import _get_inputs
from coremltools.converters.mil import Builder as mb

@register_torch_op
def new_ones(context, node):
    inputs = _get_inputs(context, node)
    shape = inputs[1]
    if isinstance(shape, (list, tuple)):
        if all(getattr(d, "val", None) is not None for d in shape):
            context.add(mb.fill(shape=np.array([int(d.val) for d in shape], dtype=np.int32), value=1.0, name=node.name))
        else:
            dims = [mb.reshape(x=mb.cast(x=d, dtype="int32"), shape=[1]) if getattr(d, "val", None) is None
                    else np.array([int(d.val)], dtype=np.int32) for d in shape]
            context.add(mb.fill(shape=mb.concat(values=dims, axis=0), value=1.0, name=node.name))
    elif shape.val is not None:
        context.add(mb.fill(shape=np.array(shape.val, dtype=np.int32), value=1.0, name=node.name))
    else:
        context.add(mb.fill(shape=mb.cast(x=shape, dtype="int32"), value=1.0, name=node.name))

m = Wav2Vec2BertForMultilevelCTC.from_pretrained("obadx/muaalem-model-v3_2").eval().float()

class PhonemeHead(torch.nn.Module):
    """Only the phoneme level: features → log-probs per frame."""
    def __init__(self, m):
        super().__init__(); self.enc = m.wav2vec2_bert; self.head = m.level_to_lm_head["phonemes"]
    def forward(self, input_features):
        h = self.enc(input_features, return_dict=False)[0]
        return torch.log_softmax(self.head(h), dim=-1)

w = PhonemeHead(m).eval()
T = 250   # 5 s of audio (50 feature frames a second after stride 2)
x = torch.randn(1, T, 160); mask = torch.ones(1, T, dtype=torch.int32)
traced = torch.jit.trace(w, (x,), strict=False)
# Up to 30 s: a slow half-line of the Shatibiyyah can run past 10 s. The
# lengths are fixed, one per second (the app pads a clip with silence to the
# next one): the Simulator's Core ML crashes on a free length, and the Neural
# Engine only takes fixed shapes.
MAX_FRAMES = int(sys.argv[2]) if len(sys.argv) > 2 else 1500
LENGTHS = list(range(50, MAX_FRAMES + 1, 50))
t0 = time.time()
ml = ct.convert(
    traced,
    inputs=[ct.TensorType(name="input_features", shape=ct.EnumeratedShapes(shapes=[(1, n, 160) for n in LENGTHS], default=(1, 250, 160)))],
    outputs=[ct.TensorType(name="log_probs")],
    compute_precision=ct.precision.FLOAT16,
    minimum_deployment_target=ct.target.iOS18,
    convert_to="mlprogram",
)
print(f"converted in {time.time()-t0:.0f}s")
ml.save(sys.argv[1] if len(sys.argv) > 1 else "MuaalemPhonemes.mlpackage")
