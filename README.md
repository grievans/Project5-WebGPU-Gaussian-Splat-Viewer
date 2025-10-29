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

![](images/Screenshot%202025-10-28%20200732.png)

This is a WebGPU-based renderer for rendering point clouds, displaying them either as single pixels or as gaussian splats—ellipsoids projected onto the screen with colors varying with viewing angle in order to reconstruct views of the scene. The user can control the scale of the splats used, making the image more sparse or solid as may be necessary for the particular input to appear realistic.

![](images/Screenshot%202025-10-28%20200822.png)

![](images/Screenshot%202025-10-28%20200850.png)

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

Changing only the size passed in to the splat preprocess pipeline without altering the sorting pipelines caused errors, so testing the full renderer with different workgroup sizes appears infeasible with the current codebase [^1]. Testing without sorting enabled, the workgroup size appeared to have no particular effect on the rest of the process, staying in the same range hovering around 9.10 fps (10.99 ms/frame) on the MacBook for workgroup sizes of 32, 64, 128, and 256 with the default gaussian multiplier of 1. I suspect the relative lack of factors like branching may be why this appeared insignificant—with the preprocess compute shader only branching to return when outside the input array length, to return when outside the view frustum, to return when the determinant is 0 (which does not appear to occur regularly, especially as we add an offset to the covariance matrix to attempt to prevent it), and at the very end to increment the dispatch count for the sorting step when at a size threshold. I suspect the sorting portion may be more heavily affected by workgroup count though cannot currently test it.

- Does view-frustum culling give performance improvement? Why do you think this is?

<img width="1918" height="1089" alt="Screen Shot 2025-10-28 at 11 34 20 PM" src="https://github.com/user-attachments/assets/01f9ae5d-ec60-46c2-8f92-0cde9e32caf3" />

The impact of culling depends on the particular scene and viewing position, but it appears to give some degree of performance improvement in any situation where we are not viewing an entire scene at once. For example, with the camera rotated to only see about half of a scene as in the above image, our run time per frame is about 51.6 ms with frustum culling and 56.2 ms without frustum culling. When parts of the scene are off-screen, we still see some performance improvement without view-frustum culling, as in our fragment shader we still automatically skip many fragments that fall outside the screen bounds, however we see further benefit in performing our own culling in the preprocess compute step as we can skip entire splats in both the sort and vertex shader steps rather than waiting until the fragment shader to see if they are relevant. 

Culling based on the near and far clip planes also provides benefit in removing bugs that can occur when moving the camera close in to the scene, as in the below image which has the bike's handlebar behind the camera position yet appearing in the top left corner of the screen.

<img width="1916" height="1086" alt="Screen Shot 2025-10-28 at 11 43 37 PM" src="https://github.com/user-attachments/assets/c0cc3b76-422c-4db8-975e-86c91f4edeee" />

- Does number of gaussians affect performance? Why do you think this is?

<img width="1917" height="1089" alt="Screen Shot 2025-10-28 at 11 52 19 PM" src="https://github.com/user-attachments/assets/1d532f73-fe39-4991-b14e-81be23bcefb1" />

Number of gaussians has a significant performance impact. For example, on the aforementioned MacBook, the bonsai scene as in the image above runs significantly faster than the bike scene shown earlier, which it has about a fourth of the points of (1063091 vs. 272956), taking about 27.39 ms per frame at an angle to see the entire scene (even with the gaussian multiplier raised to 1.5). Fewer gaussians means fewer workgroups needed for the preprocessing shader and in turn fewer elements to sort (and fewer workgroups used to sort them) in the sorting step and finally fewer splats to shade in the vertex and fragment shaders.

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
