Unreleased
- Command-line interface: validate options and exit non-zero on invalid or out-of-range arguments
- Reject malformed .obj input (out-of-range face indices) and empty geometry with a clear error instead of crashing or hanging
- Report output/report write failures instead of exiting successfully
- Run the CLI headless with no display: auto-select the offscreen Qt platform on display-less Linux; macOS and Windows use their native platform (no xvfb needed)
- macOS: build on both Apple Silicon and Intel Homebrew prefixes; use the Accelerate framework; fix a packaged-app CLI platform crash
- Linux: fix the release build on aarch64/ARM
- Contain per-island parameterization failures so one degenerate island no longer aborts the whole remesh; fix memory/resource leaks and cross-thread worker teardown
- Quiet verbose CLI diagnostics; warning-clean release build
- Add a black-box CLI test suite (run via test/run_tests.sh) and a CI test job
- Document bundled third-party dependencies in thirdparty/README.md

1.0.0
- Relicense from GPLv3 to MIT (reimplemented MIT-incompatible dependencies)
- Improve parameterizer, isotropic remesher, and quad extraction algorithms
- Add adaptivity parameter
- Add sharp edge parameter
- Add smooth normal parameter for low-poly mesh
- Replace density with target quads parameter
- Add command-line interface
- Refine main window, theme, and graphics widgets
- Replace app icon

1.0.0-beta.3
- Remesh isolated meshes separately   
- Improve quad extractor  
- Add edge scaling setting for generating low poly  
- Add rough progress reporting (Windows only)  
- Generate quad dominated mesh    
- Improve parameterization for thin surfaces  

1.0.0-beta.2
- Fix holes  
- Replace Poly budget with density setting  
- Remove laplacian smooth in preprocess  

1.0.0-beta.1
- Replace MIQ with QuadCover  
- Implement simple quad extractor  
- Remove libQEx  
- Add OpenVDB for uniform remeshing  

1.0.0-alpha.4
- Add constrained option: Better Edge Flow/Less Distortion  
- Fix libQEx access violation  
- Fix OpenMesh crash  
- Limit singularities to 320  
- Improve wireframe render  

1.0.0-alpha.3
- Support mesh with holes  
- Generate better edge flow by increase the default constraint ratio from 0.4 to 0.5  
- Alleviate spiral pattern by up-sampling  
- Speed up on complex mesh by reducing singularities   
- Add debug dialog  
