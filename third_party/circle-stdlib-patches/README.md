# Circle stdlib patches

This directory contains the local patch set for the pinned Circle stdlib v20
source archive in `third_party/source-cache/`.

The Pi4 and Pi5 VICE 3.10 build helpers apply these patches when preparing
their generated Circle stdlib trees under `build/pi4/circle-stdlib` and
`build/pi5/circle-stdlib`.

When changing Circle, regenerate the affected patch from a diff between a clean
archive extraction and the modified generated Circle tree, then verify the
patch applies cleanly to a fresh extraction before building.
