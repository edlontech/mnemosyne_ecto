defmodule MnemosyneEcto.SqliteVec do
  @moduledoc """
  Locates and downloads the precompiled `sqlite-vec` loadable extension.

  The extension is downloaded from the `asg017/sqlite-vec` GitHub releases into
  this application's `priv/sqlite_vec` directory when `mnemosyne_ecto` is compiled
  alongside `:ecto_sqlite3`. Load it on every SQLite connection:

      config :my_app, MyApp.Repo, load_extensions: [MnemosyneEcto.SqliteVec.path()]

  Vendored from the unmaintained `sqlite_vec` Hex package
  (https://github.com/joelpaulkoch/sqlite_vec, Copyright (c) 2024 Joel Koch,
  MIT License), whose `nx ~> 0.9` requirement conflicts with `nx ~> 1.0`.
  """

  alias MnemosyneEcto.SqliteVec.Downloader

  @doc "Path to the downloaded loadable library, without file extension."
  @spec path() :: String.t()
  def path, do: Application.app_dir(:mnemosyne_ecto, "priv/sqlite_vec/vec0")

  @doc """
  Downloads the loadable library for the current platform into `output_dir`.

  Skips the download when a library is already present. Raises on failure.
  """
  @spec download!(Path.t()) :: :ok
  def download!(output_dir) do
    File.mkdir_p!(output_dir)

    case Downloader.download(output_dir) do
      :skip -> :ok
      {:ok, _files, []} -> :ok
      {:ok, _files, failed} -> raise "failed to download sqlite-vec: " <> Enum.join(failed, ", ")
      {:error, message} -> raise "failed to download sqlite-vec: " <> message
    end
  end
end
