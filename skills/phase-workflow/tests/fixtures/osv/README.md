# osv-scanner fixtures

Recorded from osv-scanner 2.7.1 on 2026-11-23 with
`osv-scanner scan source --format json --no-resolve -L requirements.txt:<file>`, the source path
replaced by `<FILE>` and the vulnerable answer cut to two advisory groups.

| File | Input | Exit status |
| --- | --- | --- |
| `clean.json` | `six==1.17.0` | 0 |
| `vuln.json` | `requests==2.19.0` | 1 |

Also observed, with nothing on stdout: an empty `requirements.txt` exits 128 ("found 0 packages"),
a missing file exits 127, and `--offline` without a downloaded database exits 127. A
`requirements.txt` range is read inconsistently: `requests>=2.0` was skipped, and `flask>=2` was
read as version 2. The helper lists every unpinned line as not scanned either way. An
`osv-scanner.toml` beside the file is read and its `IgnoredVulns` suppress findings.
