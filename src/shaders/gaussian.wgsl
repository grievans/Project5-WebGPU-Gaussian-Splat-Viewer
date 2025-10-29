struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4f,
    // @location(1) center: vec2f,
    @location(1) offset: vec2f,
    @location(2) conic: vec3f,
    //TODO: information passed from vertex shader to fragment shader
};

struct Splat {
    //TODO: information defined in preprocess compute shader
    // screenPos: vec2f, // TODO 16bit instead? in NDC
    // maxRadius: f32,
    // // TODO what do I need here
    // // ^ I think quad size comes from maxRadius (treat like a square in NDC)
    // // also need conic and color info
    // conic: vec3f, // might make sense to just do mat2x2 instead? or again should I do some 16bit version
    // // TODO think will just use standard 32 bit for now then do the optimization later since extra credit?
    // color: vec4f,

    // I am uncertain in regards to the XC if they want packed f16s just for the passing or if the calculation should all be in f16 (assume the latter), think I could do the latter w/o too much work but will not bother for now so can work on writeup
    screenPos: u32,
    maxRadiusConic: array<u32,2>,
    colorOpacity: array<u32,2>
};

struct CameraUniforms {
    view: mat4x4<f32>,
    view_inv: mat4x4<f32>,
    proj: mat4x4<f32>,
    proj_inv: mat4x4<f32>,
    viewport: vec2<f32>,
    focal: vec2<f32>
};

@group(0) @binding(0)
var<storage,read> splats : array<Splat>;
@group(0) @binding(1)
var<storage,read> sort_indices : array<u32>;
@group(0) @binding(2)
var<uniform> camera: CameraUniforms;

@vertex
fn vs_main(
    @builtin(vertex_index) vIdx : u32,
    @builtin(instance_index) iIdx : u32
) -> VertexOutput {
    //TODO: reconstruct 2D quad based on information from splat, pass 
    var out: VertexOutput;
    let sIdx = sort_indices[iIdx];
    // out.position = vec4<f32>(1. ,1. , 0., 1.);
    const quadVerts = array<vec2f,6>(
        vec2f(-1.f,-1.f),
        vec2f(1.f,-1.f),
        vec2f(-1.f,1.f),
        vec2f(-1.f,1.f),
        vec2f(1.f,-1.f),
        vec2f(1.f,1.f)
    );
    // out.position = vec4f(splats[sIdx].screenPos + splats[sIdx].maxRadius * quadVerts[vIdx], 0.f, 1.f);

    let screenPos = vec2<f32>(unpack2x16float(splats[sIdx].screenPos));

    let radiusConicX = vec2<f32>(unpack2x16float(splats[sIdx].maxRadiusConic[0]));
    let conicYZ = vec2<f32>(unpack2x16float(splats[sIdx].maxRadiusConic[1]));
    let cXY = vec2<f32>(unpack2x16float(splats[sIdx].colorOpacity[0]));
    let cZW = vec2<f32>(unpack2x16float(splats[sIdx].colorOpacity[1]));

    out.position = vec4f(screenPos + radiusConicX.x * quadVerts[vIdx], 0.f, 1.f);
    
    
    // out.color = vec4f(
    //     select(0.f,1.f,iIdx < 272950),
    //     select(0.f,1.f,iIdx == 272955),
    //     select(0.f,1.f,iIdx >= 272956), 1.f);
    // out.color = vec4f(1.f,1.f,0.f, 1.f);
    // if (all(splats[sIdx].color == vec3f(0.f,0.f,0.f))) {

        // out.color = vec4f(vec3f(1.f,0.f,0.f), 1.f);
    // } else {

    // let d = (out.position.xy - splats[sIdx].screenPos) * vec2f(-camera.viewport.x, camera.viewport.y);

    // out.color = vec4f(d.x, d.y, 0.f, 1.f);
    // out.color = vec4f(splats[sIdx].color.xyz, 1.f / (1.f + exp(-splats[sIdx].color.w)));
    // out.center = splats[sIdx].screenPos;
    // out.offset = d;
    // out.conic = splats[sIdx].conic;


    let d = (out.position.xy - screenPos) * vec2f(-camera.viewport.x, camera.viewport.y);
    
    out.color = vec4f(cXY.x, cXY.y, cZW.x, 1.f / (1.f + exp(-cZW.y)));
    out.offset = d;
    out.conic = vec3f(radiusConicX.y, conicYZ.x, conicYZ.y);
    // }
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {

    // let sPos = (in.position.xy / camera.viewport * 2.f - 1.f) * vec2f(1.f, -1.f);
    // let center = (in.center.xy / camera.viewport * 2.f - 1.f) * vec2f(1.f, -1.f);
    // // let center = 
    // let d = (sPos - center) * vec2f(-camera.viewport.x, camera.viewport.y);

    let d = in.offset;

    let power = -0.5f * (in.conic.x * d.x * d.x + 
    in.conic.z * d.y * d.y) - in.conic.y * d.x * d.y;
    if (power > 0.f) {
        discard;
    }

    let alpha = clamp(0.f, 1.f, in.color.w * exp(power));
    // return vec4f(d.x, d.y, 0.f, 1.f);
    return vec4f(in.color.xyz * alpha, alpha);
    // return in.color;
    // return vec4<f32>(1.);
}