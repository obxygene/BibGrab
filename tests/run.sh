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
for input in ["https://arxiv.org/abs/2608.08120", "https://arxiv.org/pdf/2608.08120v2.pdf", "arXiv:2608.08120", "2608.08120"] {
    assert(extractDOI(input) == "10.48550/arXiv.2608.08120", input)
}
assert(arxivID("https://arxiv.org/abs/hep-th/9901001v2") == "hep-th/9901001")
assert(arxivID("https://example.org/abs/2608.08120") == nil)
assert(extractDOI("https://doi.org/10.1103/PhysRevB.98.045103") == "10.1103/PhysRevB.98.045103")
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
