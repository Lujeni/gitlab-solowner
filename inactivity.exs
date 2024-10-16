#!/usr/bin/env elixir
Mix.install([
  :req,
  {:jason, "~> 1.4"}
])

defmodule GitlabSolowners do
  @gitlab_api_url System.get_env("GITLAB_API_URL") || "https://gitlab.com/api/v4/"

  def paginate_projects(page \\ 1) do
    one_year_ago = DateTime.utc_now() |> DateTime.add(-365 * 24 * 60 * 60, :second)

    response = Req.get!("#{@gitlab_api_url}/projects?page=#{page}")
    response
    |> Map.get(:body)
    |> Enum.each(fn project ->
      IO.puts("fetch #{project["name"]}")

      "#{@gitlab_api_url}/projects/#{project["id"]}/repository/commits?per_page=1"
      |> Req.get!()
      |> Map.get(:body)
      |> Enum.each(fn commit ->
        commit_datetime = commit["created_at"] |> DateTime.from_iso8601()
        case commit_datetime do
          {:ok, datetime, _offset} ->
            if DateTime.compare(datetime, one_year_ago) == :lt do
              IO.puts("Commit from #{commit["created_at"]} is older than one year.")
            end
          _error ->
            IO.puts("Error parsing date: #{commit["created_at"]}")
        end
      end)
    end)

    headers = response.headers
    next_page = hd(headers["x-next-page"])
    if next_page  do
      paginate_projects(next_page)
    end
  end
end

# Start pagination from the first page
GitlabSolowners.paginate_projects()
