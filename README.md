# BibGrab

BibGrab is a lightweight desktop utility for retrieving BibTeX citations from DOI identifiers, publisher URLs, and arXiv links. It provides a menu bar interface on macOS and a system tray interface on Windows. Retrieved citations are displayed in the application and copied to the clipboard.

## Features

- DOI, publisher URL, and arXiv identifier support, including versioned arXiv links.
- NASA ADS search and BibTeX export with an optional API token.
- DOI content negotiation through registration agencies such as Crossref and DataCite.
- Persistent API configuration and optional launch at login.
- No application account or analytics service.

## Installation

### macOS

Requirements: macOS 13 or later and Xcode Command Line Tools. Native builds support Apple Silicon and Intel processors.

```sh
xcode-select --install
bash build.sh
open build/BibGrab.app
```

To install the application in `~/Applications` and restart the installed copy:

```sh
bash update.sh
```

Local builds use ad-hoc signing. Distribution outside a development environment requires an appropriate Developer ID signature and notarization. The build script accepts `BIBGRAB_SIGN_IDENTITY`, `BIBGRAB_ARCH`, and `BIBGRAB_OUTPUT_APP` for signing, architecture, and output configuration.

### Windows

The Windows application uses Windows Forms and .NET 10. Builds target Windows x64 by default; Windows ARM64 is also available through the build script. Windows 11 is recommended.

To obtain an automated build, open the repository's **Actions** tab, select a successful **Build and test** run, and choose the artifact that matches the deployment option:

- **BibGrab-Windows-x64-Small** is a smaller, framework-dependent executable. Install the [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/en-us/download/dotnet/10.0) first.
- **BibGrab-Windows-x64-Standalone** includes the .NET runtime and runs without a separate runtime installation. Its larger download is approximately 45 MB.

Extract the downloaded artifact and launch `BibGrab.exe`. GitHub sign-in is required to download workflow artifacts. These builds are unsigned development artifacts, not installer packages.

To build the standalone executable from source, install the [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0), then run in PowerShell from the repository root:

```powershell
./windows/build.ps1
./build/windows/win-x64/self-contained/BibGrab.exe
```

To build the smaller executable, which requires the .NET 10 Desktop Runtime on the destination computer:

```powershell
./windows/build.ps1 -SelfContained $false
./build/windows/win-x64/framework-dependent/BibGrab.exe
```

For Windows ARM64:

```powershell
./windows/build.ps1 -Runtime win-arm64
```

The standalone executable includes the .NET runtime and does not require a separate runtime installation. Store the executable in a permanent location before enabling **Launch at Login**. Closing the window leaves the application running in the system tray; use **Quit** from the tray menu to exit.

## Usage

1. Open BibGrab from the macOS menu bar or Windows system tray.
2. Enter a DOI, publisher URL, or arXiv identifier.
3. Press Return on macOS or select **Get BibTeX** on Windows.
4. Paste the copied citation into a bibliography file or reference editor.

Supported input examples:

```text
10.1103/PhysRev.47.777
https://doi.org/10.1103/PhysRev.47.777
https://arxiv.org/abs/hep-th/9711200
arXiv:hep-th/9711200
```

arXiv PDF links and version suffixes are accepted. Version suffixes are removed for citation lookup. The availability and completeness of citation metadata depend on the upstream services.

A recording guide and README embedding instructions are provided in [Usage demonstration](docs/usage-demo.md).

## API configuration

An ADS token is optional. Obtain a personal token from [NASA ADS settings](https://ui.adsabs.harvard.edu/user/settings/token), then select **Set ADS Token…** from the menu or **ADS Token…** in the Windows application.

A saved token is reused across application restarts and updates. The `ADS_API_TOKEN` environment variable is used only when no saved token exists. To remove a saved token, clear the token field and save; an existing environment variable remains available as a fallback.

When configured, BibGrab queries ADS first. If ADS cannot provide a citation, the application requests BibTeX through DOI content negotiation. Without a token, it uses DOI content negotiation directly. arXiv identifiers are mapped to arXiv-issued DOIs and searched in ADS by identifier.

## Data storage and privacy

| Platform | Token storage |
| --- | --- |
| macOS | Plaintext user preferences in the `org.bibgrab.settings` domain. |
| Windows | `%LOCALAPPDATA%\BibGrab\ads-token.dat`, encrypted with Windows Data Protection for the current user. |

Credentials are stored outside the source directory and are not included in application builds. ADS credentials are sent only to NASA ADS. Citation identifiers are sent to ADS when configured, or to `doi.org` and the metadata services to which it redirects. Retrieved citations are copied to the system clipboard.

Do not include API tokens, preference files, or private clipboard contents in issue reports or demonstration recordings.

## Command-line interface

The macOS application supports command-line citation lookup:

```sh
build/BibGrab.app/Contents/MacOS/BibGrab --doi https://arxiv.org/abs/hep-th/9711200 --no-copy
```

Remove `--no-copy` to copy the result to the clipboard. The Windows version currently provides citation lookup through its graphical interface.

## Development and validation

macOS checks:

```sh
bash tests/run.sh
bash build.sh
```

Citation service checks for the Windows implementation:

```sh
dotnet run --project windows/BibGrab.Checks -c Release
```

The citation checks use mock HTTP responses and require no API credentials or network access. They cover input normalization, ADS export, DOI fallback, authentication header isolation, invalid responses, and cancellation.

The GitHub Actions workflow builds both applications. On Windows, it also verifies encrypted token persistence and form initialization. Automated checks do not replace interactive testing of the tray menu, clipboard, display scaling, or login startup behavior.

## Troubleshooting

- **Invalid input:** supply a DOI, supported publisher URL, or arXiv identifier.
- **HTTP 401 from ADS:** verify the saved ADS token.
- **HTTP 400:** verify the identifier and the service named in the error.
- **Paper unavailable:** the metadata provider may not have indexed the record yet.
- **Connection failure:** check network access, proxy settings, and service availability.
- **Windows clipboard busy:** select **Copy** to retry; the retrieved citation remains available in the output field.

## Contributing

Issue reports should include the operating system, application version or commit, a reproducible public identifier, and the exact error message. Contributions should include relevant validation and maintain equivalent citation behavior across platforms where practical.

## License

Released under the [MIT License](LICENSE).
