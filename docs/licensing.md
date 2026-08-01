# Release licensing gate

A release must not be published until all native artifacts are inventoried.

1. Resolve and commit `pubspec.lock`.
2. Generate an SBOM.
3. Record the exact mpv/FFmpeg native libraries and codecs in the installer.
4. Determine whether GPL components are linked.
5. Include Streamlink BSD attribution.
6. Include model license and source provenance.
7. Include Flutter/plugin notices.
8. Have a human review the final installer contents.

The CI build is a technical artifact, not a legal determination.
