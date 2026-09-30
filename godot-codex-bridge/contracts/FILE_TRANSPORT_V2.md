# File-backed request completion contract

Local REL-02 contract, 2026-09-29. This applies to both MCP file polling and
the paired Host-to-addon RPC path. The request body has a UUID `request_id`;
the same ID and exact canonical body must be retained across transport attempts.
Different content under one ID is a conflict, never a new action.

1. The producer writes a same-directory temporary JSON file, flushes it, then
   renames it to `requests/<id>.json`. The addon reads only final `.json` names.
2. Before any action, the addon exclusively creates a per-ID lock directory and
   durably records an ID and canonical-body hash claim. Claim failure means no
   action. A repeat completed claim replays its
   stored result. A repeat in-progress claim returns `outcome_unknown`; it
   never attempts the action again. A hash mismatch is rejected.
3. The addon durably records the complete result before publishing an atomic
   `responses/<id>.json`. Failed response publication can be retried using the
   stored result without executing the action again.
4. A stale request is refused before claiming. Journal entries are pruned only
   after 30 minutes, well past the 600s start window (plus 120s clock skew), so
   a pruned ID can no longer start and a replay is refused as `stale_request`.
   The claim cap remains a fail-closed backstop.
5. A Host RPC refusal made before dispatch may fall back to the file path with
   the same ID: connection refused (Host not running), HTTP 403/404, or the
   error codes `bridge_rpc_unavailable`, `addon_not_connected`,
   `project_not_attached`, `project_mismatch`, `bridge_dir_mismatch`,
   `request_required`, `request_id_required`, `invalid_json_body` and
   `message_too_large`. Redirects are errors. Timeout, lost connection,
   `addon_disconnected`, `request_id_conflict` or malformed success is an
   uncertain outcome and must return that status without a fallback execution.
   A file timeout is also an uncertain outcome: callers must inspect its
   `request_id`, not retry the action under a new ID.

This gives at-most-once execution attempts and durable replay/refusal. A Godot
editor mutation and its journal are not one transaction, so a crash between
the mutation and result persistence can yield `outcome_unknown`. The product
must not report that as success or automatically repeat the mutation. Responses
must echo the request ID and the MCP client must reject mismatches.
