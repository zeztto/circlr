# Design sources and interpretation

Reviewed 2026-09-08 against local Codex CLI 0.149.1. These are design sources, not copied runtime manuals. Music-role instructions and the single-writer workflow are circlr's own contracts.

- [OpenAI model guide](https://developers.openai.com/api/docs/guides/latest-model): clear outcomes, scoped instructions and appropriate delegation informed the short entrypoint and explicit handoffs. Model names and API capabilities are not hard-coded into this kit.
- [Codex skills](https://learn.chatgpt.com/docs/build-skills): progressive disclosure and repository skill discovery informed the entrypoint/references structure.
- [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents): standalone role TOML and inherited runtime settings informed the eight custom-agent profiles. Actual concurrency depends on the host.
- [Codex App Server](https://learn.chatgpt.com/docs/app-server): skill discovery and explicit skill input inform the future in-app session integration. Validate fields against the installed version's generated schema.
- [Berklee: Music Producer](https://www.berklee.edu/careers/roles/music-producer), [Top-Line Songwriter](https://online.berklee.edu/careers-in-music/roles/top-line-songwriter), [Mixing Engineer](https://www.berklee.edu/careers/roles/mixing-engineer): distinguish creative coordination, vocal melody/lyrics and multitrack mixing. circlr adapts these responsibilities to proposals, IDs, revisions and measurable artifacts; it does not claim to reproduce a human studio team or certify generated music.
