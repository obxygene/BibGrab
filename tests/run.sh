#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP_TEST=$(mktemp -d)
trap 'rm -rf "$TMP_TEST"' EXIT
python3 - "$TMP_TEST/main.swift" <<'PYTEST'
import pathlib, sys
s = pathlib.Path('main.swift').read_text()
s = s[:s.index('// ───────────────────────────────────────────────── Entry')]
s = s.replace('UserDefaults(suiteName: "org.bibgrab.settings")!', 'UserDefaults(suiteName: "org.bibgrab.tests")!')
s += r'''
for input in ["https://arxiv.org/abs/0709.2140", "https://arxiv.org/pdf/0709.2140v2.pdf", "arXiv:0709.2140", "0709.2140"] {
    assert(extractDOI(input) == "10.48550/arXiv.0709.2140", input)
}
assert(arxivID("https://arxiv.org/abs/hep-th/9711200v2") == "hep-th/9711200")
assert(arxivID("https://example.org/abs/0709.2140") == nil)
assert(extractDOI("https://doi.org/10.1103/PhysRev.47.777") == "10.1103/PhysRev.47.777")
assert(!looksLikeDOI("invalid"))
setADSToken(" test-token ")
assert(adsToken() == "test-token")
assert(UserDefaults(suiteName: "org.bibgrab.tests")!.string(forKey: adsTokenKey) == "test-token")
setADSToken("")
assert(appPreferences.string(forKey: adsTokenKey) == nil)
print("Input normalization and settings checks passed")
'''
pathlib.Path(sys.argv[1]).write_text(s)
PYTEST
swiftc -framework Cocoa -framework ServiceManagement "$TMP_TEST/main.swift" -o "$TMP_TEST/tests"
"$TMP_TEST/tests"
