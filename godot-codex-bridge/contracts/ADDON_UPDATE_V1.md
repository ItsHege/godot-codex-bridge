# In-editor addon update contract (v1)

Local contract, 2026-09-30. Lets the Bridge dock check for and install a newer
reviewed GC-work build without a manual install command.

## Trust model

- The build source is always the trusted Host's own product checkout: its
  `addons/godot_codex_bridge`, `GC_WORK_CHANNEL.json` and `scripts/gc_work.ps1`.
  No path, script or build comes from the project or the request.
- Only the paired addon socket may call these methods. The target project is
  always the Host's attached project.
- Files are never replaced while the editor runs: the Host installs only after
  the requesting editor process has exited and its heartbeat is stale. The
  existing installer takes a backup, refuses file removal and records the new
  `install_manifest.json`.
- Nothing is saved by the Bridge. Closing uses Godot's normal close request, so
  Godot itself asks about unsaved changes; the user may cancel the close.

## Host RPC (paired only)

`addon.update.check` `{}` →
`{ state, installed_build_id, available_build_id, available_version,
   published_at, source_matches_channel, pending }`
- `state`: `current | update_available | unmanaged | drifted |
  different_channel | channel_unpublished | source_unpublished`
  (`source_unpublished`: the Host's canonical addon differs from the published
  channel build, so no reviewed build is installable).

`addon.update.schedule` `{ build_id, editor_pid, godot_executable }` →
`{ scheduled: true, update_id }`
- Rejects unless `state == update_available` and `build_id` equals the
  available build (the user confirmed exactly that build).
- `editor_pid`: positive integer, must be a live process.
  `godot_executable`: absolute path to an existing `.exe` outside the project
  root, used only to reopen the project (`--editor --path <root>`).
- One pending update per Host. Scheduling again replaces it.

`addon.update.cancel` `{}` → `{ cancelled: boolean }`

## Host behaviour after scheduling

1. Wait for `editor_pid` to exit (poll ≤1s; give up after 30 min → `cancelled`).
2. Retry the install for up to 60s until the installer no longer reports an
   active editor (heartbeat ≤5s old).
3. Run `gc_work.ps1 -Action Update -ProjectRoot <attached root>` with PowerShell 7
   (absolute Program Files path; System32 Windows PowerShell only as a fallback),
   no shell, fixed arguments. Build digests sort entries ordinally so both shells
   agree; installs recorded with the older culture-sorted digest are still
   recognised as unmodified.
4. Write `<project>/.godot/godot_codex_bridge/addon_update_result.json`:
   `{ update_id, status: installed|failed|cancelled, from_build_id,
      to_build_id, backup_path, error, finished_at }`.
5. Reopen the project with `godot_executable --editor --path <root>`
   (detached) unless cancelled. A failed install also reopens so the user sees
   the error, except when it failed because an editor is already open again.
6. While an update is scheduled or installing, `host.shutdown` is deferred until
   it finishes, and cancel is refused once installing starts. `pending` is only
   reported to the project it belongs to. Updater scripts time out (60s status,
   5 min install). The first `gc_work.ps1 -Action Update` of a project also adds
   it to the per-user GC-work project registry.

## Addon behaviour

- Bridge tab "Updates" row: status from the local install/channel manifests
  (works without the Host), `Check for updates`, `Update now`.
- `Update now` needs a paired Host (otherwise disabled with the reason and the
  manual `gc_work.ps1 -Action Update` command). It shows a confirmation with
  build ids and "Godot will close, the update installs,
  then the project reopens". On confirm: `addon.update.schedule`, then Godot's
  normal close request. If the user cancels the close, the dock shows
  "Update pending — close Godot to install" and `Cancel update`.
- On startup, a new `addon_update_result.json` is shown once in the dock.
