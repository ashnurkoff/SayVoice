# SayVoice wave S icon

Mode: built-in image_gen (generation, then background correction).
Deliverable: `sayvoice-wave-s.png`, opaque RGB PNG, 1024 × 1024, square corners.
The generated 1254 × 1254 artwork was exported at the requested size using macOS sips.
The background is visually close to #17171D, with small pixel-level color variations from generation.

## Generation prompt

Use case: logo-brand
Asset type: macOS app icon master, square 1:1, exactly 1024×1024 pixels.
Scene/backdrop: flat, solid dark #17171D filling the entire square canvas from edge to edge, including all four square corners. This is the unmasked source artwork; the user will cut the squircle afterward. Do not draw a separate inset tile or visible squircle.
Subject: one single centered object: the silhouette of an S formed entirely by a single continuous smooth sound-wave ribbon. One thick rounded flowing stroke with rounded ends, simple elegant geometric curves, clearly readable as an S-shaped wave.
Style/medium: minimalist geometric icon, high detail, crisp smooth edges, soft studio lighting with restrained surface depth.
Color palette: a smooth gradient along the ribbon from indigo #7B7FF2 to violet #A78BFA, with a subtle soft glow close to the ribbon.
Composition/framing: straight-on centered view, balanced negative space suitable for a later macOS squircle crop; the S is the sole visual object.
Constraints: no text or typography; the S-shaped wave mark is the only letter-like form. No other letters, no extra waveform lines, no frame, no border, no rounded-corner mask, no drop shadow outside the object, no background vignette or texture, no watermark. Preserve a clean flat #17171D background and square corners.

## Background correction prompt

Use case: precise-object-edit
Input image: edit target.
Change only the background and output canvas: put the existing purple S ribbon on a completely OPAQUE, FLAT SOLID #17171D background extending to every edge and all four square corners. Deliver a square 1024×1024 image. This is finished flat square artwork, NOT a transparent icon cutout. All background pixels must be fully opaque. Do not remove or key out the background. Do not create an alpha cutout.
Preserve exactly the single continuous S-shaped ribbon, its smooth rounded ends, indigo #7B7FF2 to violet #A78BFA gradient, crisp edges, studio highlights, subtle glow, centered composition and proportions. No additional objects, letters, text, border, frame, inset tile, rounded corners, squircle mask, vignette or external drop shadow.
