{{ range $type := list "Patch" "Minor" }}
---
name: Bump python3 version ({{ $type }})

scms:
  default:
    kind: github
    spec:
      user: "{{ $.github.user }}"
      email: "{{ $.github.email }}"
      owner: "{{ $.github.owner }}"
      repository: "{{ $.github.repository }}"
      token: "{{ requiredEnv $.github.token }}"
      username: "{{ $.github.username }}"
      branch: "{{ $.github.branch }}"

sources:
  currentLine:
    kind: yaml
    name: Retrieve the current Python3 line (3.x without patch)
    spec:
      file: ./provisioning/tools-versions.yml
      key: $.python3_version
    transformers:
      - findsubmatch:
          pattern: '^(\d*)\.(\d*).*'
          capturepattern: '\1.\2'
  {{ if eq (lower $type) "patch" }}
  lastVersion:
    kind: json
    name: Get the latest patch version for the current python3 line ({{ source "currentLine" }})
    spec:
      file: https://endoflife.date/api/python.json
      engine: dasel/v3
      key: 'filter(cycle=="{{ source "currentLine" }}").map(latest)[0]'
  {{ else }}
  lastVersion:
    kind: json
    name: Get the latest python3 version
    spec:
      file: https://endoflife.date/api/python.json
      engine: dasel/v3
      key: 'map(latest)[0]'
  {{ end }}

conditions:
  checkChocolateyPackage:
    kind: file
    name: Check if {{ source "lastVersion" }} is available as a Chocolatey package
    disablesourceinput: true  # Do not pass source as argument to the command line
    spec:
      file: https://community.chocolatey.org/packages/python3/{{ source "lastVersion" }}
      matchpattern: 'Package Approved'
  checkPythonSourceAvailable:
    kind: shell
    name: Check if {{ source "lastVersion" }} exists as a source tarball on python.org
    disablesourceinput: true
    spec:
      command: curl --silent --show-error --fail --head https://www.python.org/ftp/python/{{ source "lastVersion" }}/Python-{{ source "lastVersion" }}.tgz

targets:
  updateVersion:
    name: Bump `python3` version in the tools-versions.yml file to `{{ source "lastVersion" }}`
    sourceid: lastVersion
    kind: yaml
    spec:
      file: "provisioning/tools-versions.yml"
      key: "$.python3_version"
    scmid: default
  updateVersionInGoss:
    name: Bump `python3` version in goss tests to `{{ source "lastVersion" }}`
    sourceid: lastVersion
    kind: yaml
    spec:
      engine: "yamlpath"
      files:
        - tests/goss-linux.yaml
        - tests/goss-windows.yaml
      key: $.command.python3.stdout[0]
    scmid: default
  updatePythonExecInGoss:
    name:  Bump `python3` (stripped) version in Goss tests exec
    kind: yaml
    sourceid: lastVersion
    transformers:
      - findsubmatch:
          pattern: '(\d+\.\d+)\.\d+'
          capturepattern: '/usr/local/bin/python\1 --version'
    spec:
      # TODO: update Windows tests too when they'll specify a specific minor version
      files:
        - tests/goss-linux.yaml
      key: $.command.python3.exec
    scmid: default

actions:
  patchBumps:
    kind: github/pullrequest
    title: 'feat: bump `python3` ({{ lower $type }}) version to `{{ source "lastVersion" }}`'
    scmid: default
    spec:
      labels:
        - enhancement
        - python3
        - linux
        - windows
        - {{ (lower $type) }}-bump
...
{{ end }}
