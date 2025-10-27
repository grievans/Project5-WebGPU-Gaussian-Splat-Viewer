const SH_C0: f32 = 0.28209479177387814;
const SH_C1 = 0.4886025119029199;
const SH_C2 = array<f32,5>(
    1.0925484305920792,
    -1.0925484305920792,
    0.31539156525252005,
    -1.0925484305920792,
    0.5462742152960396
);
const SH_C3 = array<f32,7>(
    -0.5900435899266435,
    2.890611442640554,
    -0.4570457994644658,
    0.3731763325901154,
    -0.4570457994644658,
    1.445305721320277,
    -0.5900435899266435
);

override workgroupSize: u32;
override sortKeyPerThread: u32;

struct DispatchIndirect {
    dispatch_x: atomic<u32>,
    dispatch_y: u32,
    dispatch_z: u32,
}

struct SortInfos {
    keys_size: atomic<u32>,  // instance_count in DrawIndirect
    //data below is for info inside radix sort 
    padded_size: u32, 
    passes: u32,
    even_pass: u32,
    odd_pass: u32,
}

struct CameraUniforms {
    view: mat4x4<f32>,
    view_inv: mat4x4<f32>,
    proj: mat4x4<f32>,
    proj_inv: mat4x4<f32>,
    viewport: vec2<f32>,
    focal: vec2<f32>
};

struct RenderSettings {
    gaussian_scaling: f32,
    sh_deg: f32,
}

struct Gaussian {
    pos_opacity: array<u32,2>,
    rot: array<u32,2>,
    scale: array<u32,2>
};

struct Splat {
    //TODO: store information for 2D splat rendering

    // TODO optimize to 16 bit XC
    screenPos: vec2f, // in NDC
    maxRadius: f32,
    conic: vec3f,
    color: vec3f,
};

//TODO: bind your data here
@group(0) @binding(0)
var<uniform> camera: CameraUniforms;

@group(1) @binding(0)
var<storage,read> gaussians : array<Gaussian>;
@group(1) @binding(1)
var<storage,read_write> splats : array<Splat>;


@group(2) @binding(0)
var<storage, read_write> sort_infos: SortInfos;
@group(2) @binding(1)
var<storage, read_write> sort_depths : array<u32>;
@group(2) @binding(2)
var<storage, read_write> sort_indices : array<u32>;
@group(2) @binding(3)
var<storage, read_write> sort_dispatch: DispatchIndirect;

/// reads the ith sh coef from the storage buffer 
fn sh_coef(splat_idx: u32, c_idx: u32) -> vec3<f32> {
    //TODO: access your binded sh_coeff, see load.ts for how it is stored
    return vec3<f32>(0.0);
}

// spherical harmonics evaluation with Condon–Shortley phase
fn computeColorFromSH(dir: vec3<f32>, v_idx: u32, sh_deg: u32) -> vec3<f32> {
    var result = SH_C0 * sh_coef(v_idx, 0u);

    if sh_deg > 0u {

        let x = dir.x;
        let y = dir.y;
        let z = dir.z;

        result += - SH_C1 * y * sh_coef(v_idx, 1u) + SH_C1 * z * sh_coef(v_idx, 2u) - SH_C1 * x * sh_coef(v_idx, 3u);

        if sh_deg > 1u {

            let xx = dir.x * dir.x;
            let yy = dir.y * dir.y;
            let zz = dir.z * dir.z;
            let xy = dir.x * dir.y;
            let yz = dir.y * dir.z;
            let xz = dir.x * dir.z;

            result += SH_C2[0] * xy * sh_coef(v_idx, 4u) + SH_C2[1] * yz * sh_coef(v_idx, 5u) + SH_C2[2] * (2.0 * zz - xx - yy) * sh_coef(v_idx, 6u) + SH_C2[3] * xz * sh_coef(v_idx, 7u) + SH_C2[4] * (xx - yy) * sh_coef(v_idx, 8u);

            if sh_deg > 2u {
                result += SH_C3[0] * y * (3.0 * xx - yy) * sh_coef(v_idx, 9u) + SH_C3[1] * xy * z * sh_coef(v_idx, 10u) + SH_C3[2] * y * (4.0 * zz - xx - yy) * sh_coef(v_idx, 11u) + SH_C3[3] * z * (2.0 * zz - 3.0 * xx - 3.0 * yy) * sh_coef(v_idx, 12u) + SH_C3[4] * x * (4.0 * zz - xx - yy) * sh_coef(v_idx, 13u) + SH_C3[5] * z * (xx - yy) * sh_coef(v_idx, 14u) + SH_C3[6] * x * (xx - 3.0 * yy) * sh_coef(v_idx, 15u);
            }
        }
    }
    result += 0.5;

    return  max(vec3<f32>(0.), result);
}

@compute @workgroup_size(workgroupSize,1,1)
fn preprocess(@builtin(global_invocation_id) gid: vec3<u32>, @builtin(num_workgroups) wgs: vec3<u32>) {
    let idx = gid.x;
    //TODO: set up pipeline as described in instruction
    if (idx >= arrayLength(&gaussians)) {
        return;
    }
    // TODO mostly placeholder
    // TODO culling, conic etc.
    let vertex = gaussians[idx];
    let a = unpack2x16float(vertex.pos_opacity[0]);
    let b = unpack2x16float(vertex.pos_opacity[1]);
    // let viewPos = camera.view * vec4<f32>(a.x, a.y, b.x, 1.);
    // if (viewPos.z < )
    var pos = camera.proj * camera.view * vec4<f32>(a.x, a.y, b.x, 1.);
    pos /= pos.w; 
    // NDC -> 1.2x screen size = +/- 1.2
    // want [-1.2,1.2] unculled; and in front of the camera 
    if (abs(pos.x) > 1.2 || abs(pos.y) > 1.2 || pos.z < 0.f) {
        return;
    }
    // splats[idx] = Splat(pos.xy, 0.05, vec3f(0.f,0.f,0.f), vec3f(1.f,0.f,0.f));
    // can I use sort_infos.keys_size in the above? I don't totally get how we want to set up the data in splats
    //  oh wait looking at the specification it returns the original value 
    let splatIdx = atomicAdd(&sort_infos.keys_size, 1u);
    splats[splatIdx] = Splat(pos.xy, 0.05, vec3f(0.f,0.f,0.f), vec3f(1.f,0.f,0.f));
    // atomicAdd(&sort_dispatch.dispatch_x, 1u);
    
    // TODO need these placeholders it seems like on this version of WebGPU to not have an error from the bindGroupLayout differing from the optimized-out form
    //  TODO make sure to remove when properly setting up use for them
    sort_depths[splatIdx] = 0; // TODO
    sort_indices[splatIdx] = splatIdx;
    // }

    let keys_per_dispatch = workgroupSize * sortKeyPerThread; 
    // increment DispatchIndirect.dispatchx each time you reach limit for one dispatch of keys
    if (splatIdx % keys_per_dispatch == 0) {
        // ^TODO is that the right comparison?
        // I guess it's splatIdx / keys_per_dispatch > dispatch_x?
        //  can't directly check dispatch_x for that comparison though w/ being atomic
        //  so modulo to check when at a multiple?
        atomicAdd(&sort_dispatch.dispatch_x, 1u);
        

    }
}