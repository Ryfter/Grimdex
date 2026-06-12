<!-- EXAMPLE promotion candidate, drawn (sanitized) from real use. This is the format
     the promotions inbox README describes: a cross-project rule proposed into
     universal/promotions/<project-id>.md, conflict-checked and inscribed by the
     daily sweep — never written into the law directly. -->

## Personal data lives outside the app's source tree
**Proposed rule:** Apps built for personal use but shared publicly never keep personal
data files in their own source tree. Personal files live in a private parallel tree
`<PERSONAL_ROOT>/<project-id>/` — itself one private repo, so a single push backs up
every project's personal data. The app finds its folder via an env var or config value
(`<APP>_DATA_DIR`), defaulting to the OS user-data directory (`%LOCALAPPDATA%\<App>`,
`$XDG_DATA_HOME`) so a cold clone works for strangers out of the box. Credentials never
go in the personal tree — they belong in a password manager, or encrypted into the app
repo (dotenvx/SOPS). Litmus test (12-factor): the codebase must be open-sourceable at
any moment without compromising anything personal — structurally (data physically
elsewhere), not procedurally (.gitignore discipline).
**Evidence:** Research fan-out across community practice: the parallel-private-tree
pattern is the established dotfiles model (chezmoi/Stow/vcsh) generalized to project
data. `.gitignore`-only protection is the weakest line — secrets have been recovered
at scale even from force-push-deleted commits (Truffle Security) — and gitignored
files are otherwise unbacked-up entirely. Windows note: prefer pointing the app at the
tree over symlinks/junctions (admin/Developer-Mode friction; cloud-sync clients handle
links unreliably); `mklink /J` is the fallback for apps that need files in-place.
**Also seen in:** none yet — filed at convention creation so the sweep can track
adoption (acceptance needs ≥2 projects).
**Filed:** 2026-06-12
