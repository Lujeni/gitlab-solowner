#!/usr/bin/env elixir
Mix.install([
  :req,
  {:jason, "~> 1.4"}
])

defmodule GitlabSolowners do
  @gitlab_api_url System.get_env("GITLAB_API_URL") || "https://gitlab.com/api/v4"
  @gitlab_api_token System.get_env("GITLAB_API_TOKEN")
  @one_year_ago DateTime.utc_now() |> DateTime.add(-365 * 24 * 60 * 60, :second)

  def check_commit(req, project) do
    try do
      Req.get!(req, url: "/projects/#{project["id"]}/repository/commits?per_page=1")
      |> Map.get(:body)
      |> Enum.each(fn commit ->
        commit_datetime = commit["created_at"] |> DateTime.from_iso8601()
        case commit_datetime do
          {:ok, datetime, _offset} ->
            if DateTime.compare(datetime, @one_year_ago) == :lt do
              IO.puts("#{project["namespace"]["path"]},#{project["path"]},#{commit["created_at"]}")
            end
          _error ->
            IO.puts("Error parsing date: #{commit["created_at"]}")
        end
      end)
    rescue
      e -> IO.puts("Error retrieve commits from #{project["path"]} #{inspect(e)}")
    end
  end

  def get_projects(req, page \\ 1) do
    response = Req.get!(req, url: "/projects?page=#{page}&per_page=1000")
    response
    |> Map.get(:body)
    |> Enum.each(fn project ->
      check_commit(req, project)
    end)

    headers = response.headers
    next_page = hd(headers["x-next-page"])
    if next_page  do
      get_projects(req, next_page)
    end
  end

  def run() do
    req = Req.new(base_url: @gitlab_api_url, auth: {:bearer, @gitlab_api_token}, http_errors: :raise)
    get_projects(req)
  end
end

GitlabSolowners.run()
