# The web export template, slimmed to what HOT EXFIL uses: built by .github/workflows (scons
# profile=this file) from Godot's own source at the same version as the editor. Everything here is
# only left out of the browser build; the editor and the desktop builds are untouched.
#
# What the game uses, and so what stays: 3D with the Compatibility renderer, 3D physics (one
# StaticBody3D and ray casts, on Godot's own physics: the project never picks Jolt), the plain
# text server (the pixel font is a bitmap the game draws itself, ASCII only), RichTextLabel (the
# HUD), JavaScriptBridge (iPhone checks), audio synthesised into WAVs at run time, textures
# imported lossless (kept as WebP inside the .pck, so WebP stays), FreeType and Brotli (the
# engine's own fallback font is a WOFF2 it loads at start-up).

platform = "web"
# target=template_release is given on the command line: the web platform sets its own default
# target over this file.
threads = "no"
production = "yes"
# The smallest link: one optimisation pass over the whole engine at once (slower to build).
lto = "full"
optimize = "size"
# The old-API shims stay (deprecated=yes, the default): the game calls Image.create(), which a
# build without them doesn't have.

# Whole parts of the engine the game has no use for.
disable_physics_2d = "yes"
disable_navigation_2d = "yes"
disable_navigation_3d = "yes"
disable_xr = "yes"
# ZIP packs (the game loads a .pck, not a .zip).
minizip = "no"

# Modules: none unless listed. Left out, among others: Jolt physics, navigation, XR, the advanced
# text server (ICU and HarfBuzz), Ogg/Vorbis/MP3/Theora, JPG/SVG/KTX/DDS/TGA/BMP/HDR/EXR loaders
# and the texture compressors (every texture is already imported), glTF/FBX (models are imported
# as scenes), CSG, GridMap, noise, RegEx, networking (ENet, WebRTC, WebSocket, multiplayer, UPnP,
# mbedTLS), the camera, interactive music, visual shaders and ZIP.
modules_enabled_by_default = "no"
module_gdscript_enabled = "yes"
module_godot_physics_3d_enabled = "yes"
module_text_server_fb_enabled = "yes"
module_freetype_enabled = "yes"
module_webp_enabled = "yes"
