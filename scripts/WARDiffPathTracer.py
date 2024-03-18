from falcor import *

def render_graph_WARDiffPathTracer(maxBounces=0, spp=1):
    g = RenderGraph("WARDiffPathTracer")
    WARDiffPathTracer = createPass("WARDiffPathTracer",
                                   {
                                       "maxBounces": maxBounces,
                                       "samplesPerPixel": spp,
                                       "diffMode": "ForwardDiffDebug",
                                    #    "diffMode": "BackwardDiffDebug",
                                       "diffVarName": "CBOX_BUNNY_TRANSLATION",
                                       "sampleGenerator": 0,  # 0: tiny uniform; 1: uniform
                                   })
    g.addPass(WARDiffPathTracer, "WARDiffPathTracer")

    AccumulatePassPrimal = createPass("AccumulatePass", {"enabled": True, "precisionMode": "Single"})
    g.addPass(AccumulatePassPrimal, "AccumulatePassPrimal")

    AccumulatePassDiff = createPass("AccumulatePass", {"enabled": True, 'precisionMode': "Single"})
    g.addPass(AccumulatePassDiff, "AccumulatePassDiff")
    ColorMapPassDiff = createPass("ColorMapPass", {"minValue": -4.0, "maxValue": 4.0, "autoRange": False})
    g.addPass(ColorMapPassDiff, "ColorMapPassDiff")

    g.addEdge("WARDiffPathTracer.color", "AccumulatePassPrimal.input")
    g.addEdge("WARDiffPathTracer.dColor", "AccumulatePassDiff.input")
    g.addEdge("AccumulatePassDiff.output", "ColorMapPassDiff.input")
    g.markOutput("AccumulatePassDiff.output")
    g.markOutput("AccumulatePassPrimal.output")
    g.markOutput("ColorMapPassDiff.output")
    return g

WARDiffPathTracer = render_graph_WARDiffPathTracer(4, 8)  # max bounces, sample per pixel
try: m.addGraph(WARDiffPathTracer)
except NameError: None

flags = SceneBuilderFlags.DontMergeMaterials | SceneBuilderFlags.RTDontMergeDynamic | SceneBuilderFlags.DontOptimizeMaterials
m.loadScene("test_scenes/bunny_war_diff_pt.pyscene", buildFlags=flags)
