import sys, coremltools as ct
import coremltools.optimize.coreml as cto
m = ct.models.MLModel("MuaalemPhonemes.mlpackage")
kind = sys.argv[1]
if kind == "int8":
    cfg = cto.OptimizationConfig(global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8", granularity="per_channel"))
    q = cto.linear_quantize_weights(m, cfg)
else:
    bits = int(kind.replace("pal", ""))
    cfg = cto.OptimizationConfig(global_config=cto.OpPalettizerConfig(nbits=bits, mode="kmeans", granularity="per_grouped_channel", group_size=16))
    q = cto.palettize_weights(m, cfg)
q.save(f"Muaalem_{kind}.mlpackage")
