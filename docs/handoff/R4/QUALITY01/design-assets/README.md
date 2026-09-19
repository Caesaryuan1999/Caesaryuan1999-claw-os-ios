# Original Figma voice assets

Read-only export from file `CreMqit00K1MAJju69YoOv`, page `248:1115`, via the original nodes' `exportAsync({format: 'PDF'})`. No canvas node was created or changed. These files are preparation assets, not evidence of running UIKit.

- `voice-wave.pdf`: node `338:1674`, nominal vector geometry 16 × 20 pt. The exported PDF MediaBox is 18 × 22.000038 pt because its stroke extends beyond that geometry. Rendering must retain the original scale (nominal frame plus approximately 1 pt stroke allowance on each edge), rather than fitting the whole PDF into 16 × 20 and shrinking the drawing.
- `voice-tail.pdf`: node `338:1675`, original PDF MediaBox 6 × 12 pt. The real six-point graphic must fit; the earlier plan's five-point placement allowance is not permission to crop the PDF. Tail size is excluded from the bubble-body duration formula.

`manifest.json` records original byte lengths and SHA-256 values. No PDF rewrite, recoloring, stretching, or recreated path was applied. A later asset catalog may use template tint and direction mirroring. Actual rendering size, clipping and padding remain subject to real UIKit geometry and PNG verification in the visual unit.

The local optional PDF-preview attempt did not run because PyMuPDF is not installed. No dependency was installed and no preview was fabricated. Original Figma design-context visuals were already read; these PDFs remain byte-for-byte exports.
