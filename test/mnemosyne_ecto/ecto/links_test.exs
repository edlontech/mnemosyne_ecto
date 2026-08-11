defmodule MnemosyneEcto.Ecto.LinksTest do
  use ExUnit.Case, async: true

  alias Mnemosyne.Graph.Edge
  alias MnemosyneEcto.Ecto.Links

  describe "type/0" do
    test "returns :map" do
      assert Links.type() == :map
    end
  end

  describe "cast/1" do
    test "accepts maps" do
      links = Edge.empty_links()
      assert {:ok, ^links} = Links.cast(links)
    end

    test "rejects non-maps" do
      assert :error = Links.cast("invalid")
      assert :error = Links.cast(42)
    end
  end

  describe "dump/1" do
    test "converts atom keys and MapSets to string keys and lists" do
      links =
        Map.put(Edge.empty_links(), :membership, MapSet.new(["a", "b"]))

      assert {:ok, dumped} = Links.dump(links)

      assert is_binary(hd(Map.keys(dumped)))
      assert Enum.sort(dumped["membership"]) == ["a", "b"]
      assert dumped["hierarchical"] == []
    end

    test "rejects non-maps" do
      assert :error = Links.dump("nope")
    end
  end

  describe "load/1" do
    test "converts string keys and lists to atom keys and MapSets" do
      json = %{
        "membership" => ["a", "b"],
        "hierarchical" => [],
        "provenance" => [],
        "sibling" => []
      }

      assert {:ok, loaded} = Links.load(json)

      assert loaded.membership == MapSet.new(["a", "b"])
      assert loaded.hierarchical == MapSet.new()
    end

    test "loads nil as empty links" do
      assert {:ok, loaded} = Links.load(nil)
      assert loaded == Edge.empty_links()
    end

    test "loads empty map filling missing edge types" do
      assert {:ok, loaded} = Links.load(%{})
      assert loaded == Edge.empty_links()
    end

    test "rejects non-maps" do
      assert :error = Links.load(42)
    end
  end

  describe "dump/load round-trip" do
    test "preserves link structure" do
      links =
        Edge.empty_links()
        |> Map.put(:provenance, MapSet.new(["x", "y", "z"]))
        |> Map.put(:sibling, MapSet.new(["w"]))

      assert {:ok, dumped} = Links.dump(links)
      assert {:ok, loaded} = Links.load(dumped)

      assert loaded == links
    end
  end
end
