defmodule MnemosyneEcto.SqliteVec.Downloader do
  @moduledoc false

  use OctoFetch,
    latest_version: "0.1.5",
    github_repo: "asg017/sqlite-vec",
    download_versions: %{
      "0.1.5" => [
        {:darwin, :amd64, "1daa90b7cdda7e873af4636a20a2b6daf0ebd4d664f2bbbcc2ffeae219bf34b6"},
        {:darwin, :arm64, "348ea4ce39b4b4749b19ee93e5e9674d6ed7616e3e313cb20f6354cdecbebc75"},
        {:linux, :amd64, "626bb9b66896269facdf7f87d94c308bf0523cb1e584ff7ff5b3f51936f21d24"},
        {:linux, :arm64, "8ce460c1f2adcbbc709f5ca1d1a3578c34c62c131d1a044bd3ff7c0729be2137"},
        {:windows, :amd64, "cfd31e96d2edf27749c4c2063134737fc98ac87b6e113acf204db57563b078bc"}
      ]
    }

  @impl true
  def download_name(version, :darwin, arch), do: download_name(version, :macos, arch)
  def download_name(version, os, :amd64), do: download_name(version, os, :x86_64)
  def download_name(version, os, :arm64), do: download_name(version, os, :aarch64)
  def download_name(version, os, arch), do: "sqlite-vec-#{version}-loadable-#{os}-#{arch}.tar.gz"

  @impl true
  def pre_download_hook(_file, output_dir) do
    if output_dir |> Path.join("vec0.*") |> Path.wildcard() == [], do: :cont, else: :skip
  end
end
