# BibGrab

A small macOS menu bar app that turns DOI, publisher, and arXiv links into BibTeX and copies the result to your clipboard.

## Build and install

Requires macOS 13 or later and Xcode Command Line Tools (`xcode-select --install`). No third-party dependencies. Builds natively on Apple Silicon or Intel.

```sh
bash build.sh
open build/BibGrab.app
```

To install into `~/Applications` and restart the installed app:

```sh
bash update.sh
```

Local builds are ad-hoc signed. Public binary distribution requires your own Developer ID signing and Apple notarization; this project does not include signing credentials. Set `BIBGRAB_SIGN_IDENTITY` to use your own signing identity. `BIBGRAB_ARCH` optionally selects a target architecture.

## Usage

Click the book icon in the menu bar, paste a DOI or arXiv link, and press Return. A successful lookup displays BibTeX and copies it. Right-click the icon for settings and Launch at Login.

Accepted examples:

- `10.1103/PhysRev.47.777`
- `https://doi.org/10.1103/PhysRev.47.777`
- `https://arxiv.org/abs/hep-th/9711200`
- `arXiv:hep-th/9711200` (PDF URLs and version suffixes also work)

ADS is preferred when configured. Otherwise the app uses DOI content negotiation, which routes to Crossref or DataCite. An arXiv identifier is normalized to its arXiv-issued DOI; ADS is searched by arXiv identifier. Very recent records may not yet be indexed by either service.

## Optional ADS API token

Obtain your own token at https://ui.adsabs.harvard.edu/user/settings/token and use **Set ADS Token…** once. The saved token becomes the default across restarts, rebuilds, and terminal launches. Clear the field and save to remove it. `ADS_API_TOKEN` is an optional fallback when no saved token exists.

The token is stored in your macOS user preferences (`org.bibgrab.settings`), outside this repository, in plaintext. Do not share your preferences file or token. No credentials are bundled. The token is sent only to NASA ADS; DOI requests go to doi.org and its metadata-service redirects. There is no analytics service.

## Terminal usage

```sh
build/BibGrab.app/Contents/MacOS/BibGrab --doi https://arxiv.org/abs/hep-th/9711200 --no-copy
```

Omit `--no-copy` to also copy the citation.

## Checks

```sh
bash tests/run.sh
```

These checks run without network access or real credentials. Network errors include the failing service/status; if both ADS and DOI lookup fail, both errors are shown. A 401 indicates an invalid ADS token; a 400 can indicate malformed input. Check the identifier before changing your token.

## Contributing

Open an issue with the input identifier, macOS version, and error text. Never include API tokens or preferences dumps. Keep changes dependency-free where practical and run the checks and build before submitting a pull request.

## License

MIT — see [LICENSE](LICENSE).
