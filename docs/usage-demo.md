# Usage demonstration

A short animated demonstration can be embedded directly in the project README. The recording should show a complete citation retrieval workflow without exposing personal settings or unrelated desktop content.

## Recording sequence

1. Open BibGrab from the menu bar or system tray.
2. Enter `https://doi.org/10.1103/PhysRev.47.777`.
3. Submit the lookup and wait for the citation to appear.
4. Paste the citation into an empty bibliography document.

Record only the relevant application area. Use a duration of approximately 10–20 seconds, readable text, and a clearly visible pointer. Exclude token dialogs, account details, notifications, and unrelated windows. Use an actual application recording so that the demonstration accurately reflects the interface.

On macOS, use [Screenshot](https://support.apple.com/en-tm/guide/mac-help/mh26782/mac) by pressing **Shift–Command–5** to record a selected portion of the screen. On Windows, use the recording mode in [Snipping Tool](https://support.microsoft.com/en-us/windows/apps/use-snipping-tool-to-capture-screenshots). Save the recording, trim inactive sections, and export it as a GIF using a video editor or FFmpeg.

## GIF conversion

With [FFmpeg](https://www.ffmpeg.org/ffmpeg-filters.html) installed, the following command creates a compact GIF with a generated color palette:

```sh
ffmpeg -i usage.mp4 -filter_complex "fps=10,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" -loop 0 docs/images/usage.gif
```

Adjust the width and frame rate as needed to preserve readability. Keep the file small enough to load promptly on the repository page.

## README integration

After saving the GIF at `docs/images/usage.gif`, insert the following Markdown after the introductory paragraph in `README.md`:

```markdown
![BibGrab retrieving a BibTeX citation and copying it to the clipboard](docs/images/usage.gif)
```

Commit the image and the README change together:

```sh
git add README.md docs/images/usage.gif
git commit -m "Add usage demonstration"
git push
```

For separate platform demonstrations, use `usage-macos.gif` and `usage-windows.gif` with descriptive alternative text. Do not add an image reference before the corresponding file exists.
