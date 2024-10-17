#!/usr/bin/env elixir
Mix.install([
  :req,
  {:jason, "~> 1.4"}
])

require Logger

defmodule GitlabSolowners do
  @gitlab_api_url System.get_env("GITLAB_API_URL") || "https://gitlab.com/api/v4"
  @gitlab_api_token System.get_env("GITLAB_API_TOKEN")
  @one_year_ago DateTime.utc_now() |> DateTime.add(-365 * 24 * 60 * 60, :second)

  def check_commit(req, project, file_path) do
    try do
      Req.get!(req, url: "/projects/#{project["id"]}/repository/commits?per_page=1")
      |> Map.get(:body)
      |> Enum.each(fn commit ->
        commit_datetime = commit["created_at"] |> DateTime.from_iso8601()

        case commit_datetime do
          {:ok, datetime, _offset} ->
            if DateTime.compare(datetime, @one_year_ago) == :lt do
              row = "#{project["namespace"]["path"]},#{project["path"]},#{commit["created_at"]}"
              File.write(file_path, "#{row}\n", [:append])
            end

          _error ->
            Logger.info("Error parsing date: #{commit["created_at"]}")
        end
      end)
    rescue
      e -> Logger.info("Error retrieve commits from #{project["path"]} #{inspect(e)}")
    end
  end

  def get_projects(req, page \\ 1, file_path) do
    response = Req.get!(req, url: "/projects?page=#{page}&per_page=100")

    tasks =
      response
      |> Map.get(:body)
      |> Enum.map(fn project ->
        Logger.info("handle #{project["path_with_namespace"]}")

        Task.async(fn ->
          check_commit(req, project, file_path)
        end)
      end)

    Task.await_many(tasks)

    headers = response.headers
    current_page = String.to_integer(hd(headers["x-page"]))
    next_page = current_page + 1
    total_page = String.to_integer(hd(headers["x-total-pages"]))

    if next_page <= total_page do
      Logger.info("Next pagination #{current_page}-#{next_page} on #{total_page}")
      get_projects(req, next_page, file_path)
    end
  end

  def run() do
    #
    timestamp = :os.system_time(:millisecond)
    random_part = :crypto.strong_rand_bytes(8) |> Base.encode16() |> String.downcase()
    filename = "#{timestamp}_#{random_part}"
    file_path = Path.join(["/tmp", filename])
    File.write(file_path, "")
    Logger.info("Generate file #{file_path}")

    #
    req =
      Req.new(base_url: @gitlab_api_url, auth: {:bearer, @gitlab_api_token}, http_errors: :raise)

    get_projects(req, 1, file_path)
  end
end

GitlabSolowners.run()
