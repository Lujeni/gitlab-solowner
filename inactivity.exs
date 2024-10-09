#!/usr/bin/env elixir
Mix.install([
  :req,
  {:jason, "~> 1.4"}
])

one_year_ago = DateTime.utc_now() |> DateTime.add(-365 * 24 * 60 * 60, :second)

"https://gitlab.com/api/v4/projects"
|> Req.get!()
|> Map.get(:body)
|> Enum.each(fn project -> 
  "https://gitlab.com/api/v4/projects/#{project["id"]}/repository/commits?per_page=1"
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
