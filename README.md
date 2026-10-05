# open-shaders release test

End-to-end harness for the release attach workflow of
[open-shaders](https://github.com/alandtse/open-shaders). It runs the real
`_attach-release-artifacts.yaml` (copied unmodified by `sync-from-open-shaders.sh`)
against synthetic build artifacts and checks the draft release it produces, then
deletes the draft and its tag. Nothing here ships a product; there is no Nexus
upload and no secrets.

Run one scenario per workflow run (the attach workflow downloads artifacts by fixed name):

    ./sync-from-open-shaders.sh <path to an open-shaders checkout>   # then commit and push
    gh workflow run e2e-attach.yaml -f scenario=valid

Scenarios: `valid`, `bad-se-cache`, `truncated-vr-blob`, `no-caches`, `no-clang`,
`bad-clang-dll`, `aio-without-dll`. See `e2e/verify_release.py` for what each expects.

Not covered: re-attach preserving an existing asset (a draft release has no tag, so
`gh release download <tag>` cannot see it).
