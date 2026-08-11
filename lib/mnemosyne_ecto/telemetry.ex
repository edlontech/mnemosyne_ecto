defmodule MnemosyneEcto.Telemetry do
  @moduledoc """
  Telemetry events for `MnemosyneEcto`.

  All events are emitted via `:telemetry.span/3`, which automatically
  produces `:start`, `:stop`, and `:exception` suffixed events.

  ## Events

  ### `[:mnemosyne_ecto, :find_candidates]`

  Emitted when searching for candidate nodes via vector similarity.

    * **Metadata:** `%{node_types: [atom()], tenant_id: String.t(), repo_id: String.t()}`
    * **Extra stop measurements:** `%{candidate_count: non_neg_integer()}`

  ### `[:mnemosyne_ecto, :apply_changeset]`

  Emitted when applying a changeset (inserts, links, metadata).

    * **Metadata:** `%{tenant_id: String.t(), repo_id: String.t()}`
    * **Extra stop measurements:** `%{nodes_inserted: non_neg_integer()}`

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

  @doc "Wraps `fun` in a `:telemetry.span/3` under the `[:mnemosyne_ecto, event]` prefix."
  @spec span(atom(), map(), (-> {result, map()})) :: result when result: term()
  def span(event, metadata, fun) do
    :telemetry.span(@prefix ++ [event], metadata, fun)
  end
end
