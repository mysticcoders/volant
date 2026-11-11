# Marketing renders

Everything here draws the real Volant views with fictional data, compiled with the release asset catalog. Nothing is an HTML rebuild of the app.

- `main.swift` (`tools/render-marketing.sh`): the light and dark launcher captures on the website.
- `demo.swift` (`tools/render-demo.sh`): the README's animated launcher demo.
- `video/` (`tools/render-video.sh`): the 10-feature demo video.

## Feature video

```sh
tools/render-video.sh                 # every scene and the end card
tools/render-video.sh --scenes 3,0    # only scene 3 and the end card
VOLANT_VIDEO_FRAMES=/path/to/images tools/render-video.sh   # encode earlier frames again, no VM
```

It needs the `volant-render-27` Tart VM and its SSH key (see docs/ui-testing.md) and `ffmpeg` on the host. The views run only in the headless VM, never on your desktop; there is no host fallback.

1. `tools/render-vm.py --video` compiles `video/render.swift` with the app sources on the host, bundles it with `video/scenes.json`, the app icon and the website's iPhone capture, and runs it in the VM. It writes 1080x1080 frames named `volant-video-SS-NNNN-MS.png`: scene SS (00 is the end card), frame NNNN, shown for MS milliseconds.
2. `video/encode.py` encodes them with ffmpeg: `dist-video/clips/NN-title.mp4` per scene, each starting with its title card, and `dist-video/volant-features.mp4` with all ten and the end card. Both are H.264, yuv420p, 30 fps, `+faststart`, no audio. `dist-video/` is ignored by git.

`video/scenes.json` holds each scene's number, card title, caption, qualifying note, fixture and scripted steps: typed text (one character per frame), keys, cursor moves and clicks, fixture hooks and how long each frame shows. Change the script there; change a fixture or hook in `render.swift`. When the UI changes, run the script again and look at the frames before using the video.

The title cards and captions use the system typeface (SF Pro, as the app does) on the website's dark colors from `website/app/home.css`. The site declares Geist but doesn't load it.

What the video can't show, and how it handles it:

- **Pick Color:** the macOS color loupe is system UI on a real display, so the scene shows a crosshair over a fictional poster, then the real color card from a fake sampler.
- **Focus:** the notch is a fake notch rectangle, as in the launcher fixture; nothing is really hidden and no browser tab is blanked.
- **Breaks:** no camera or microphone is read; the caption states the behavior.
- **AI Chat:** no provider runs; the conversation is fictional text drawn by the real conversation view.
- **Notes in iCloud:** the Mac window is the real notes panel; the iPhone is the existing simulator capture in `website/public/images/iphone/note.webp`, which shows the same fictional note. No iCloud sync runs.
