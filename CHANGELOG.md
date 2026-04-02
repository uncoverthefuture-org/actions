# Changelog

## [1.3.1](https://github.com/uncoverthefuture-org/actions/compare/v1.3.0...v1.3.1) (2026-04-02)


### Bug Fixes

* use corepack instead of yarn, skip scripts on install ([#41](https://github.com/uncoverthefuture-org/actions/issues/41)) ([5f38edc](https://github.com/uncoverthefuture-org/actions/commit/5f38edcd02bdf9c8b6507cba1d886561d627d24f))

## [1.3.0](https://github.com/uncoverthefuture-org/actions/compare/v1.2.1...v1.3.0) (2026-04-02)


### Features

* add yarn + npx support and Jest tests ([#37](https://github.com/uncoverthefuture-org/actions/issues/37)) ([b3cff3e](https://github.com/uncoverthefuture-org/actions/commit/b3cff3e93d66f915c7aa49bc3213d90efacd8dc0))


### Bug Fixes

* update package name to @uncver/actions ([bbe60fb](https://github.com/uncoverthefuture-org/actions/commit/bbe60fb82c012c15af8bc4c5c9c0a1fd546d8e6f))
* update package name to @uncver/actions ([4007f23](https://github.com/uncoverthefuture-org/actions/commit/4007f2324fca4ae8965f55bb5a5da077982d4c4c))

## [1.2.1](https://github.com/uncoverthefuture-org/actions/compare/v1.2.0...v1.2.1) (2026-04-01)


### Bug Fixes

* relax nounset during .env sourcing ([d86e073](https://github.com/uncoverthefuture-org/actions/commit/d86e073cb31bfc3f2c7641b8e13c7d06f37068ba))
* restore deleted docs and deploy-docs.yml changes ([7c908d3](https://github.com/uncoverthefuture-org/actions/commit/7c908d362604c716d9b10e86005316666f0221f1))

## [1.2.0](https://github.com/uncoverthefuture-org/actions/compare/v1.1.2...v1.2.0) (2026-03-27)


### Features

* Docs Pipeline Overlay Migration ([18165b8](https://github.com/uncoverthefuture-org/actions/commit/18165b8b9897028c686a440c643288cd7094233a))
* migrate ui mapping arrays to config ts ([740b6b9](https://github.com/uncoverthefuture-org/actions/commit/740b6b9b1ec01ae416dd7e7a666b7ff3674ece58))
* restructure docs layout to dynamic overlay ([e76bfc7](https://github.com/uncoverthefuture-org/actions/commit/e76bfc7d1bae99ea9e9967dcdd137f299b48f1b4))


### Bug Fixes

* configure PAT for cross-repo sync and set absolute UI routes ([dc19aee](https://github.com/uncoverthefuture-org/actions/commit/dc19aee75230c72d339ce3e443b29cdee60bfce1))
* **docs:** upgrade CDN fonts to HTTPS to bypass Mixed Content blocks and inject router basename to resolve GitHub Pages blank-screen ([c54518a](https://github.com/uncoverthefuture-org/actions/commit/c54518a20d4d22424f20d86eb13f156eba412b7c))
* **docs:** upgrade CDN fonts to HTTPS to bypass Mixed Content blocks and inject router basename to resolve GitHub Pages blank-screen ([71e6b55](https://github.com/uncoverthefuture-org/actions/commit/71e6b55df24ead9d173889e55c03b6eaa6f591fe))
* Enable Cross-Repo Docs Overlay Pipeline ([2b7511f](https://github.com/uncoverthefuture-org/actions/commit/2b7511f729bd87e796090ec06f90147074bd3844))

## [1.1.2](https://github.com/uncoverthefuture-org/actions/compare/v1.1.1...v1.1.2) (2026-03-26)


### Bug Fixes

* **ci:** re-orient docs deployment evaluation to master push contexts to bypass Pages environment pull_request blocks ([eb880f0](https://github.com/uncoverthefuture-org/actions/commit/eb880f02cf7e9a1ad47bd313e56de46a20e09e22))

## [1.1.1](https://github.com/uncoverthefuture-org/actions/compare/v1.1.0...v1.1.1) (2026-03-26)


### Bug Fixes

* **docs:** synchronize yarn.lock after package rename to satisfy stri… ([f71fb8a](https://github.com/uncoverthefuture-org/actions/commit/f71fb8a97745179cd4753f9ac3c4605a8b75b98e))
* **docs:** synchronize yarn.lock after package rename to satisfy strict CI execution ([27b3cb1](https://github.com/uncoverthefuture-org/actions/commit/27b3cb1189cbce81816bae47c5e28078e46b2ee5))

## [1.1.0](https://github.com/uncoverthefuture-org/actions/compare/v1.0.231...v1.1.0) (2026-03-26)


### Features

* add github pages docs deployment workflow and integrate uncover-docs template ([f083df8](https://github.com/uncoverthefuture-org/actions/commit/f083df8c989d09275bb6d52646e2028340ef9a1c))
* **ci:** github pages documentation architecture and release-please automation ([98f6fbe](https://github.com/uncoverthefuture-org/actions/commit/98f6fbe720a736c77809a82d1e6722e77d90b2aa))
* GitHub Pages Documentation Site ([16895ef](https://github.com/uncoverthefuture-org/actions/commit/16895efc291754a905dd89989bbdf81eaaf75ef7))


### Bug Fixes

* **ci:** use github context expression to resolve IDE strict-environment linking ([56e089f](https://github.com/uncoverthefuture-org/actions/commit/56e089f61a1ae77d83d4f698c629695ff4018e98))
* **ci:** wrap environment string in expression to bypass strict linter warnings and restore permissions ([e52831e](https://github.com/uncoverthefuture-org/actions/commit/e52831e4423f1f850e1486108e75fde5b76696d3))
* **deploy:** refine traefik defaults, quadlet ports, and probe timeouts ([d6ccb83](https://github.com/uncoverthefuture-org/actions/commit/d6ccb8368443f8abb2567b6d4e905d46d5c50c80))
* **deploy:** Traefik Deployment Pipeline & Defaults ([28f93f4](https://github.com/uncoverthefuture-org/actions/commit/28f93f49256ac1558de84c73afb74ae1e30f2dd3))
* use dynamic delimiter for github action json parser ([99ae1cc](https://github.com/uncoverthefuture-org/actions/commit/99ae1cc1131c8f9a586d87cd665c3949447cc996))
