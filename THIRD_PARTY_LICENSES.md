# Third-Party Licenses

dsh-mini bundles the following third-party components. Each package's own
LICENSE file ships inside `app\node_modules\` and `home\profiles\web\node_modules\`
in the installer; the entries below summarize the main ones.

| Component | Version | License | Upstream |
| --- | --- | --- | --- |
| @deepseek-ai/dsh (DeepSeek Harness) | 0.1.1-rc.2 | MIT | https://github.com/deepseek-ai/deepseek-harness |
| dshmarket | 1.40.0 | MIT | https://github.com/dsh-market/dsh-market |
| Node.js runtime | 24.x | MIT | https://nodejs.org/ |
| commander | ^15 | MIT | npm |
| js-yaml | ^4 | MIT | npm |
| undici | ^7 | MIT | npm |

Notes:

- All npm dependencies are installed by pnpm from the public npm registry at
  build time; their exact license texts remain in each package folder.
- The whale-maid artwork (tray icon, desktop icon, wizard image) is AI-generated
  by the project author and is distributed under this project's MIT license.
- The installer itself is built with Inno Setup 6 (freeware; not redistributed
  inside the package).
