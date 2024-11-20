#!/usr/bin/env elixir
Mix.install([
  :req,
  {:jason, "~> 1.4"}
])

require Logger

defmodule GitlabSolowners do
  @type args :: [String.t()]
  @type opts :: %{optional(atom()) => term()}
  @type project :: %{
          id: integer(),
          path: String.t(),
          namespace: %{path: String.t()},
          path_with_namespace: String.t()
        }
  @type commit :: %{created_at: String.t(), author_email: String.t()}
  @type registry_repository :: %{id: integer(), path: String.t()}
  @type req :: Req.Request.t()
  @type file_path :: String.t()

  @default_gitlab_api_url "https://gitlab.com/api/v4"
  # Define the time boundary to consider a commit as inactive (two years ago)
  @one_year_ago DateTime.utc_now() |> DateTime.add(-365 * 2 * 24 * 60 * 60, :second)

  @spec parse_args(args()) :: {opts(), [String.t()], [String.t()]}
  def parse_args(args) do
    OptionParser.parse(args,
      switches: [help: :boolean, url: :string, token: :string, paginate: :boolean],
      aliases: [h: :help, u: :url, t: :token, p: :paginate]
    )
  end

  # Fetches commit activity from a project and writes inactive repositories to a file
  @spec check_activity(req(), project(), file_path()) :: :ok
  def check_activity(req, project, file_path) do
    try do
      Req.get!(req, url: "/projects/#{project["id"]}/repository/commits?per_page=1")
      |> Map.get(:body)
      |> Enum.each(fn commit ->
        commit_datetime = commit["created_at"] |> DateTime.from_iso8601()

        case commit_datetime do
          {:ok, datetime, _offset} ->
            if DateTime.compare(datetime, @one_year_ago) == :lt do
              row =
                "#{project["namespace"]["path"]},#{project["path"]},#{commit["created_at"]},None"

              File.write(file_path, "#{row}\n", [:append])
            end

          _error ->
            Logger.info("Error parsing date: #{commit["created_at"]}")
        end
      end)
    rescue
      e -> Logger.info("Error retrieving commits from #{project["path"]}: #{inspect(e)}")
    end
  end

  # Analyzes the authors of the repository to find dominant committers
  @spec check_authors(req(), project(), file_path()) :: :ok
  def check_authors(req, project, file_path) do
    try do
      authors =
        Req.get!(req, url: "/projects/#{project["id"]}/repository/commits?per_page=100")
        |> Map.get(:body)
        |> Enum.map(fn commit -> commit["author_email"] end)
        |> Enum.frequencies()

      total_commits = Enum.reduce(authors, 0, fn {_key, value}, acc -> acc + value end)

      authors_per_percent =
        Enum.map(authors, fn {name, count} -> {name, count / total_commits * 100} end)

      Enum.each(authors_per_percent, fn {item, percentage} ->
        if percentage > 80 do
          row = "#{project["namespace"]["path"]},#{project["path"]},None,#{item}"
          File.write(file_path, "#{row}\n", [:append])
        end
      end)
    rescue
      e -> Logger.info("Error retrieving commits from #{project["path"]}: #{inspect(e)}")
    end
  end

  @spec check_registries(req(), project(), file_path()) :: :ok
  def check_registries(req, project, _file_path) do
    Req.get!(req, url: "/projects/#{project["id"]}/registry/repositories")
    |> Map.get(:body)
    |> Enum.map(fn registry_repository ->
      response =
        Req.get!(req, url: "/registry/repositories/#{registry_repository["id"]}?size=True")

      case Map.get(response.body, "size") do
        nil ->
          Logger.info(
            "Registry repository #{registry_repository["path"]} has no size information."
          )

        size ->
          Logger.info("Registry repository #{registry_repository["path"]} has size: #{size}.")
      end
    end)
  end

  # Fetches all GitLab projects and processes them in pages, checking for activity and authors
  @spec get_projects(req(), integer(), boolean(), file_path()) :: :ok
  def get_projects(req, page \\ 1, gitlab_api_paginate, file_path) do
    response = Req.get!(req, url: "/projects?archived=False&page=#{page}")

    # Create tasks to check activity for each project concurrently
    activity_tasks =
      response
      |> Map.get(:body)
      |> Enum.map(fn project ->
        Logger.info("Handling #{project["path_with_namespace"]}")
        Task.async(fn -> check_activity(req, project, file_path) end)
      end)

    # Create tasks to check authorship for each project concurrently
    authors_tasks =
      response
      |> Map.get(:body)
      |> Enum.map(fn project ->
        Task.async(fn -> check_authors(req, project, file_path) end)
      end)

    registries_tasks =
      response
      |> Map.get(:body)
      |> Enum.map(fn project ->
        Task.async(fn -> check_registries(req, project, file_path) end)
      end)

    Task.await_many(activity_tasks)
    Task.await_many(authors_tasks)
    Task.await_many(registries_tasks)

    headers = response.headers
    current_page = String.to_integer(hd(headers["x-page"]))
    next_page = current_page + 1
    total_page = String.to_integer(hd(headers["x-total-pages"]))

    if gitlab_api_paginate and next_page <= total_page do
      Logger.info("Next pagination #{current_page}-#{next_page} on #{total_page}")
      get_projects(req, next_page, gitlab_api_paginate, file_path)
    end
  end

  def run(args) do
    {opts, _, _} = parse_args(args)

    if opts[:help] do
      IO.puts("""
      Usage: gitlab_solowners [options]

      Options:
        -h, --help        Show this help message
        -u, --url         GitLab API URL (default: #{@default_gitlab_api_url})
        -t, --token       GitLab API Token (required if not set via environment variable)
        -p, --paginate    GitLab API Paginate (required if not set via environment variable)
      """)

      System.halt(0)
    end

    gitlab_api_url = opts[:url] || System.get_env("GITLAB_API_URL") || @default_gitlab_api_url
    gitlab_api_token = opts[:token] || System.get_env("GITLAB_API_TOKEN")
    gitlab_api_paginate = opts[:paginate] || System.get_env("GITLAB_API_PAGINATE") || false

    if gitlab_api_token == nil do
      Logger.error("GitLab API Token is required. Use --token or set GITLAB_API_TOKEN.")
      System.halt(1)
    end

    timestamp = :os.system_time(:millisecond)
    random_part = :crypto.strong_rand_bytes(8) |> Base.encode16() |> String.downcase()
    filename = "#{timestamp}_#{random_part}"
    file_path = Path.join(["/tmp", filename])
    File.write!(file_path, "")
    Logger.info("Generated file #{file_path}")

    req =
      Req.new(base_url: gitlab_api_url, auth: {:bearer, gitlab_api_token}, http_errors: :raise)

    get_projects(req, 1, gitlab_api_paginate, file_path)
  end
end

GitlabSolowners.run(System.argv())
