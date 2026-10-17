import sys, coremltools as ct
import coremltools.optimize.coreml as cto
# quant.py KIND [IN.mlpackage]: KIND is int8 or palN (N-bit palettes)
kind = sys.argv[1]
m = ct.models.MLModel(sys.argv[2] if len(sys.argv) > 2 else "MuaalemPhonemes.mlpackage")
if kind == "int8":
    cfg = cto.OptimizationConfig(global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8", granularity="per_channel"))
    q = cto.linear_quantize_weights(m, cfg)
else:
    bits = int(kind.replace("pal", ""))
    cfg = cto.OptimizationConfig(global_config=cto.OpPalettizerConfig(nbits=bits, mode="kmeans", granularity="per_grouped_channel", group_size=16))
    q = cto.palettize_weights(m, cfg)
q.save(f"Muaalem_{kind}.mlpackage")
