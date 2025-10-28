import { PointCloud } from '../utils/load';
import preprocessWGSL from '../shaders/preprocess.wgsl';
import renderWGSL from '../shaders/gaussian.wgsl';
import { get_sorter,c_histogram_block_rows,C } from '../sort/sort';
import { Renderer } from './renderer';

export interface GaussianRenderer extends Renderer {

}

// Utility to create GPU buffers
const createBuffer = (
  device: GPUDevice,
  label: string,
  size: number,
  usage: GPUBufferUsageFlags,
  data?: ArrayBuffer | ArrayBufferView
) => {
  const buffer = device.createBuffer({ label, size, usage });
  if (data) device.queue.writeBuffer(buffer, 0, data);
  return buffer;
};
// ^TODO maybe should swap to using that; forgot it was here. same functionality though


export default function get_renderer(
  pc: PointCloud,
  device: GPUDevice,
  presentation_format: GPUTextureFormat,
  camera_buffer: GPUBuffer,
  renderSettingsBuffer: GPUBuffer,
): GaussianRenderer {

  const sorter = get_sorter(pc.num_points, device);
  
  // ===============================================
  //            Initialize GPU Buffers
  // ===============================================

  const nulling_data = new Uint32Array([0]);

  const nullBuffer = createBuffer(
    device, 
    "null buffer", 
    4, 
    GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST, 
    nulling_data
  );

  const splatBuffer = device.createBuffer({
    label: 'splat data buffer',
    // TODO size for 16bit
    size: pc.num_points * 4*12,  // buffer size multiple of 4?
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC,
    // mappedAtCreation: false,
  });

  // TODO
  const indirectData = new Uint32Array(4);
  indirectData[0] = 6;
  indirectData[1] = pc.num_points;
  indirectData[2] = 0;
  indirectData[3] = 0;
  // console.log(pc.num_points);

  // TODO should do mappedAtCreation thing I think? or wait we have to write later anyway so maybe fine
  const indirectBuffer = device.createBuffer({
    label: "indirect draw buffer",
    size: 16, // TODO 
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.INDIRECT
  });
  device.queue.writeBuffer(indirectBuffer, 0, indirectData, 0, indirectData.length);
  // ===============================================
  //    Create Compute Pipeline and Bind Groups
  // ===============================================
  const preprocess_pipeline = device.createComputePipeline({
    label: 'preprocess',
    layout: 'auto',
    compute: {
      module: device.createShaderModule({ code: preprocessWGSL }),
      entryPoint: 'preprocess',
      constants: {
        workgroupSize: C.histogram_wg_size,
        sortKeyPerThread: c_histogram_block_rows,
      },
    },
  });
  // let test1 = preprocess_pipeline.getBindGroupLayout(2);
  // console.log(test1);

  const sort_bind_group = device.createBindGroup({
    label: 'sort gaussian preprocess bind group',
    layout: preprocess_pipeline.getBindGroupLayout(2),
    entries: [
      { binding: 0, resource: { buffer: sorter.sort_info_buffer } },
      { binding: 1, resource: { buffer: sorter.ping_pong[0].sort_depths_buffer } },
      { binding: 2, resource: { buffer: sorter.ping_pong[0].sort_indices_buffer } },
      { binding: 3, resource: { buffer: sorter.sort_dispatch_indirect_buffer } },
    ],
  });

  // const gaussian_bind_group = device.createBindGroup({
  //   label: 'point cloud gaussians',
  //   layout: preprocess_pipeline.getBindGroupLayout(1),
  //   entries: [
  //     {binding: 0, resource: { buffer: pc.gaussian_3d_buffer }},
  //   ],
  // });
  // TODO need to invoke preprocess pipeline I think still?

  // ===============================================
  //    Create Render Pipeline and Bind Groups
  // ===============================================

  // TODO figure out what if any of this I need to change
  //  ^ different buffer I think? splats rather than Gaussian struct directly?
  //   or is it meant to be both? I don't totally understand the distinction
  const render_shader = device.createShaderModule({code: renderWGSL});
  const render_pipeline = device.createRenderPipeline({
    label: 'gaussian render',
    layout: 'auto',
    vertex: {
      module: render_shader,
      entryPoint: 'vs_main',
    },
    fragment: {
      module: render_shader,
      entryPoint: 'fs_main',
      targets: [{ format: presentation_format }],
    },
    // primitive: {
    //   topology: 'point-list',
    // },
  });

  const camera_bind_group = device.createBindGroup({
    label: 'gaussian splat camera',
    layout: preprocess_pipeline.getBindGroupLayout(0),
    entries: [
      {binding: 0, resource: { buffer: camera_buffer }}
    ],
  });
  
  const gaussian_bind_group = device.createBindGroup({
    label: 'gaussian splat compute bind group',
    layout: preprocess_pipeline.getBindGroupLayout(1),
    entries: [
      {binding: 0, resource: { buffer: pc.gaussian_3d_buffer }},
      {binding: 1, resource: { buffer: splatBuffer }},
      {binding: 2, resource: { buffer: pc.sh_buffer}}
    ],
  });
  const renderSettings_bind_group = device.createBindGroup({
    label: 'render settings bind group',
    layout: preprocess_pipeline.getBindGroupLayout(3),
    entries: [
      {binding: 0, resource: { buffer: renderSettingsBuffer }},
    ],
  });
  
  // const splatBuffer // TODO
  const splat_bind_group = device.createBindGroup({
    label: 'splat bind group',
    layout: render_pipeline.getBindGroupLayout(0),
    entries: [
      {binding: 0, resource: {buffer: splatBuffer}},
      { binding: 1, resource: { buffer: sorter.ping_pong[0].sort_indices_buffer } },
    ],
  });

  // ===============================================
  //    Command Encoder Functions
  // ===============================================
  // TODO not sure where this should be done exactly/if this is what's meant to be in this part
  const preprocess = (encoder: GPUCommandEncoder) => {
    const pass = encoder.beginComputePass({
      label: 'gaussian splat preprocess',
      // colorAttachments: [
      //   {
      //     view: texture_view,
      //     loadOp: 'clear',
      //     storeOp: 'store',
      //   }
      // ],
    });
    pass.setPipeline(preprocess_pipeline);
    pass.setBindGroup(0, camera_bind_group);
    pass.setBindGroup(1, gaussian_bind_group);
    pass.setBindGroup(2, sort_bind_group);
    pass.setBindGroup(3, renderSettings_bind_group);

    // TODO bind pc.sh_buffer... <----------

    // pass.draw(pc.num_points);
    pass.dispatchWorkgroups(Math.ceil(pc.num_points / C.histogram_wg_size));
    // TODO make sure dispatch is done right
    pass.end();
  };
  const render = (encoder: GPUCommandEncoder, texture_view: GPUTextureView) => {
    const pass = encoder.beginRenderPass({
      label: 'splat render',
      colorAttachments: [
        {
          view: texture_view,
          loadOp: 'clear',
          storeOp: 'store',
        }
      ],
    });
    pass.setPipeline(render_pipeline);
    // pass.setBindGroup(0, camera_bind_group);
    pass.setBindGroup(0, splat_bind_group);
    
    // const uint32 = new Uint32Array(); // TODO figure out indirect
    // TODO use drawIndirect? not sure if that's what they mean <------
    // pass.draw(6, 5); 
    // pass.draw(6, pc.num_points); 
    pass.drawIndirect(indirectBuffer, 0);
    // pass.draw(pc.num_points); 
    
    pass.end();
    // console.log(splatBuffer);
  };

  // ===============================================
  //    Return Render Object
  // ===============================================
  
  return {
    frame: (encoder: GPUCommandEncoder, texture_view: GPUTextureView) => {
      // reset incrementing values
      // apparently copying better than calling write from CPU side (https://webgpufundamentals.org/webgpu/lessons/webgpu-optimization.html)
      encoder.copyBufferToBuffer(nullBuffer, 0, sorter.sort_info_buffer, 0, 4);
      encoder.copyBufferToBuffer(nullBuffer, 0, sorter.sort_dispatch_indirect_buffer, 0, 4);
      // encoder.copyBufferToBuffer(indirectBuffer, 0, sorter.sort_dispatch_indirect_buffer, 0, 4);
      
      // TODO anything else to reset
      preprocess(encoder); // TODO is this the right order?
      // encoder.copyBufferToBuffer(nullBuffer, 0, sorter.sort_dispatch_indirect_buffer, 0, 4);
      // const arr = new Uint32Array([30]);
      // device.queue.writeBuffer(sorter.sort_info_buffer, 0, arr, 0, arr.length);
      // encoder.copyBufferToBuffer(nullBuffer2, 0, sorter.sort_info_buffer, 0, 4);

      // console.log(sorter.sort_dispatch_indirect_buffer);


      
      

      // OH Might just be this out of date computer/webgpu version has issues running it?
      //  but weird it just freezes/slows to nothing rather than giving an error
      sorter.sort(encoder); // TODO reenable 
      // TODO sort causes whole thing to freeze atm dunno why
      encoder.copyBufferToBuffer(sorter.sort_info_buffer, 0, indirectBuffer, 4, 4);
      // device.queue.

      render(encoder, texture_view);
    },
    camera_buffer,
  };
}
