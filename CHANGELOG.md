# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- New `:ot_attributes` option to set default Open Telemetry metadata attributes to be added to each Telepoison request
- New otel semantic conventions library to ensure proper conventions are followed

### Changed

- Span name contains `method` only now, as per semantic conventions
- `http.url` will be stripped of credentials. (eg. if the url is `"https://username:password@www.example.com/"` the attribute's value will be `"https://www.example.com/"`)

---

## [1.1.2] - 2023-01-25

### Added

- New `"net.peer.name"` attribute
- HTTPoison 2.0.0 is now supported

[Unreleased]: https://github.com/primait/teleplug/compare/1.1.2...HEAD
[1.1.2]: https://github.com/primait/teleplug/releases/tag/1.1.2
