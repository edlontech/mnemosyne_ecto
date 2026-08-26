defmodule MnemosyneEcto.Telemetry do
  @moduledoc """
  Telemetry events for `MnemosyneEcto`.

  All events are emitted via `:telemetry.span/3`. Each event name below is
  suffixed with `:start` and either `:stop` or `:exception`.

  ## Events

  ### `[:mnemosyne_ecto, :get_ingestion]`

  Emitted when loading a durable ingestion record.

    * **Start metadata:** `%{tenant_id: String.t(), repo_id: String.t(), source_id: String.t()}`
    * **Stop metadata:** start metadata plus `%{status: :found | :missing | :error}`
    * **Extra stop measurements:** `%{record_count: 0 | 1}`

  ### `[:mnemosyne_ecto, :commit_ingestion]`

  Emitted when atomically committing an ingestion record and its graph changes.

    * **Start metadata:** `%{tenant_id: String.t(), repo_id: String.t(), source_id: String.t()}`
    * **Stop metadata:** start metadata plus `%{status: :inserted | :existing | :conflict | :error}`
    * **Extra stop measurements:** `%{record_inserted: 0 | 1, nodes_inserted: non_neg_integer()}`

  Ingestion events never include payload digests, receipt bodies, or node ID
  lists. Returned conflicts and normalized storage failures emit stop events;
  only uncaught exceptions emit exception events.

  ### `[:mnemosyne_ecto, :find_candidates]`

  Emitted when searching for candidate nodes via vector similarity.

    * **Start metadata:** `%{node_types: [atom()], tenant_id: String.t(), repo_id: String.t()}`
    * **Stop metadata:** `%{candidate_count: non_neg_integer()}`

  ### `[:mnemosyne_ecto, :apply_changeset]`

  Emitted when applying a changeset (inserts, links, metadata).

    * **Start metadata:** `%{tenant_id: String.t(), repo_id: String.t()}`
    * **Stop metadata:** `%{nodes_inserted: non_neg_integer()}`

  ### `[:mnemosyne_ecto, :delete_nodes]`

  Emitted when deleting nodes.

    * **Metadata:** `%{tenant_id: String.t(), repo_id: String.t(), node_count: non_neg_integer()}`

  ### `[:mnemosyne_ecto, :get_node]`

  Emitted when fetching a single node by ID.

    * **Metadata:** `%{tenant_id: String.t(), repo_id: String.t(), node_id: String.t()}`

  ### `[:mnemosyne_ecto, :get_nodes_by_type]`

  Emitted when fetching all nodes of given types.

    * **Metadata:** `%{tenant_id: String.t(), repo_id: String.t(), node_types: [atom()]}`
  """

  @prefix [:mnemosyne_ecto]

  @type span_return(result) ::
          {result, stop_metadata :: map()}
          | {result, extra_measurements :: map(), stop_metadata :: map()}

  @doc """
  Wraps `fun` in a `:telemetry.span/3` under the `[:mnemosyne_ecto, event]` prefix.

  Two-element callback returns treat their map as stop metadata. Three-element
  callback returns merge the second map into stop measurements and treat the
  third map as stop metadata.
  """
  @spec span(atom(), map(), (-> span_return(result))) :: result when result: term()
  def span(event, metadata, fun) do
    :telemetry.span(@prefix ++ [event], metadata, fun)
  end
end
