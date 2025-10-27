struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4f,
    //TODO: information passed from vertex shader to fragment shader
};

struct Splat {
    //TODO: information defined in preprocess compute shader
    screenPos: vec2f, // TODO 16bit instead? in NDC
    maxRadius: f32,
    // TODO what do I need here
    // ^ I think quad size comes from maxRadius (treat like a square in NDC)
    // also need conic and color info
    conic: vec3f, // might make sense to just do mat2x2 instead? or again should I do some 16bit version
    // TODO think will just use standard 32 bit for now then do the optimization later since extra credit?
    color: vec3f,
};

@group(0) @binding(0)
var<storage,read> splats : array<Splat>;


@vertex
fn vs_main(
    @builtin(vertex_index) vIdx : u32,
    @builtin(instance_index) iIdx : u32
) -> VertexOutput {
    //TODO: reconstruct 2D quad based on information from splat, pass 
    var out: VertexOutput;
    // out.position = vec4<f32>(1. ,1. , 0., 1.);
    const quadVerts = array<vec2f,6>(
        vec2f(-1.f,-1.f),
        vec2f(1.f,-1.f),
        vec2f(-1.f,1.f),
        vec2f(-1.f,1.f),
        vec2f(1.f,-1.f),
        vec2f(1.f,1.f)
    );

    out.position = vec4f(splats[iIdx].screenPos + splats[iIdx].maxRadius * quadVerts[vIdx], 0.f, 1.f);
    out.color = vec4f(splats[iIdx].color, 1.f);
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return in.color;
    // return vec4<f32>(1.);
}