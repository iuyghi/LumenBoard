# Third-party technical reference notice

LumenBoard's descriptor generator was independently implemented after studying the public source of:

- PosterForge — https://github.com/mubixbyte/PosterForge
- Relevant source: `Daemon/PFPosterBuilder.m`, particularly `installItem:error:`, `writeIndexAt:width:height:error:`, `writeEmptyLayerAt:error:`, and `buildAnimationAt:source:kind:maxFPS:blurred:error:`.
- PosterForge's repository declares the MIT License: https://github.com/mubixbyte/PosterForge/blob/main/LICENSE

The current LumenBoard source does not copy or include PosterForge source files. This notice credits the source-derived technical reference. If substantial source code is later copied or adapted, preserve the applicable copyright and MIT permission notice and update this notice accordingly.

No third-party wallpaper or Apple wallpaper assets are included. Public `.tendies` packages can contain assets subject to separate copyright and redistribution terms; a repository's software license does not automatically license those assets.
