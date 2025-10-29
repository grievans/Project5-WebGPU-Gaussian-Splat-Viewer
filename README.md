# Project5-WebGPU-Gaussian-Splat-Viewer

**University of Pennsylvania, CIS 565: GPU Programming and Architecture, Project 5**

* Griffin Evans
* Tested on: Windows 11 Education, i9-12900F @ 2.40GHz 64.0GB, NVIDIA GeForce RTX 3090 (Levine 057 #1) on Google Chrome

## Live Demo

[![](https://github.com/grievans/Project5-WebGPU-Gaussian-Splat-Viewer/blob/main/images/Screenshot%202025-10-28%20194238%20packed%20f16s.png)](https://grievans.github.io/Project5-WebGPU-Gaussian-Splat-Viewer/)

In addition to the page linked in the image above, use of the demo requires a .ply file of point cloud data and a .json file of camera positional data.

## Demo Video/GIF

https://github.com/user-attachments/assets/0f0d214b-f67a-47e7-85a1-ef576ebfa30a

## Overview

This is a WebGPU-based renderer for rendering point clouds, displaying them either as single pixels or as gaussian splats—ellipsoids projected onto the screen with colors varying with viewing angle in order to reconstruct views of the scene.

## Analysis

- Compare your results from point-cloud and gaussian renderer, what are the differences?

<img width="1916" height="1091" alt="Screen Shot 2025-10-28 at 10 28 29 PM" src="https://github.com/user-attachments/assets/301d1bef-5c06-4348-af84-a372a06756c2" />

On the desktop used to test this project as mentioned above, both of the renderers produced frames in 16.67 ms—having their framerate capped by Chrome based on the monitor's refresh rate such that they were apparently identical in performance despite the additional work performed in the gaussian renderer. On a weaker machine, a MacBook Pro 15-inch 2019 running macOS 10.14.6, performance differences were more noticeable, with the bicycle scene shown in the above video varying between about 13.3ms and 18.2 ms to render as a point cloud but slowing to around 110.5 ms per frame to render it as gaussian splats. However, this number is inaccurate as it leaves out the depth sorting step of the gaussian renderer, which when enabled completely freezes the browser and produces a blank screen as output on that machine. This may be a matter of some compatibility issue with the sorting algorithm code, as this test was limited to an older version of Chrome (116.0.5845.187, the last version available for macOS below 10.15), though as it did not explicitly cause an error to occur it may also be a matter of the sorting step being such a bottleneck that the weaker hardware is unable to complete it successfully without the browser locking up.

<img width="1916" height="1087" alt="Screen Shot 2025-10-28 at 10 28 16 PM" src="https://github.com/user-attachments/assets/51f02748-318e-4a17-ab15-c8dcbc6f5af7" />

Without the sorting step, the size of the quads rendered (in comparison to the single pixels used to render the point-cloud mode) seems to be a major performance detriment, as reducing the gaussian multiplier (thus reducing the scale of each splat) significantly increased the speed, going from 110.5 ms per frame as mentioned above to 21.1 ms per frame on the MacBook. However, note that these larger sized quads are key to the ability of gaussian splatting to produce solid-appearing images from the input data, in contrast to the single-pixel view of the point cloud renderer which produces significant sparseness and gaps, and hence too low a gaussian multiplier produces unconvincing results as in the image below.

<img width="1920" height="1092" alt="Screen Shot 2025-10-28 at 11 02 12 PM" src="https://github.com/user-attachments/assets/b04f32a4-4e43-426b-8ea9-31877ef3f61e" />

Additional performance impacts potentially come from the greater number of calculations needed to compute the splat data (needing covariance, conics, etc.) as compared to simply needing to multiply the position by the view and projection matrices to render a point cloud, as well as from overhead that may come with the greater amount of reading and writing from memory in constructing and passing the splat data in the compute shader and vertex/fragment shaders.

- For gaussian renderer, how does changing the workgroup-size affect performance? Why do you think this is?

Attempts at testing different workgroup sizes with the full gaussian renderer did not reveal a noticeable performance impact, however testing was limited by the output appearing incomplete when using lower workgroup sizes. For sizes below 256, it appears that the sorting skips some number of the splats, with which are left out varying from frame-to-frame such that the image has parts flicker and disappear as in the image below:

![](images/Screenshot%202025-10-28%20203758%20128.png)

Changing only the size passed in to the splat preprocess pipeline without altering the sorting pipelines caused errors, so testing the full renderer with different workgroup sizes appears infeasible with the current codebase [^1]. Testing without sorting enabled, the workgroup size appeared to have no particular effect on the rest of the process, staying in the same range hovering around 9.10 fps (10.99 ms/frame) on the MacBook for workgroup sizes of 32, 64, 128, and 256 with the default guassian multiplier of 1. I suspect the relative lack of factors like branching may be why this appeared insignificant—with the preprocess compute shader only branching to return when outside the input array length, to return when outside the view frustum, to return when the determinant is 0 (which does not appear to occur regularly, especially as we add an offset to the covariance matrix to attempt to prevent it), and at the very end to increment the dispatch count for the sorting step when at a size threshold.

- Does view-frustum culling give performance improvement? Why do you think this is?
- Does number of guassians affect performance? Why do you think this is?

## Bloopers

![](images/Screenshot%202025-10-28%20192735.png)

![](images/Screenshot%202025-10-28%20193414.png)

Both of the above images show visual distortions caused by using the wrong values when changing the input variables in the vertex shader to use 16-bit floats packed into u32s; the first shows the max radius of the splat being used instead of the first term of the conic matrix, and the second shows the opacity value being the negation of what was intended.


[^1]: Addendum: I've realized in writing this how to change this (via line 335 in preprocess.wgsl) but I don't have access to the other machine to test at the moment


## Credits

- [Vite](https://vitejs.dev/)
- [tweakpane](https://tweakpane.github.io/docs//v3/monitor-bindings/)
- [stats.js](https://github.com/mrdoob/stats.js)
- [wgpu-matrix](https://github.com/greggman/wgpu-matrix)
- Special Thanks to: Shrek Shao (Google WebGPU team) & [Differential Guassian Renderer](https://github.com/graphdeco-inria/diff-gaussian-rasterization)
