# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshGraphLaw.TemplateQuerySyncTest do
  @moduledoc """
  ggen's frontmatter schema has no way to include a query file, so each `templates/*.tmpl` carries
  its SELECT inline. `queries/*.rq` stays the canonical, reviewable copy; this test refuses drift
  between the two, and refuses a query file no template uses.

  Real files, no parsing shortcuts beyond the fixed shape the templates are written in:
  `sparql:` then `  <name>: |` then the query indented four spaces.
  """

  # UNSUPPORTED(generator-capability): hand-written Chicago test.
  use ExUnit.Case, async: true

  @templates Path.wildcard("templates/*.tmpl")
  @queries Path.wildcard("queries/*.rq")

  defp frontmatter(path) do
    ["", front | _] = path |> File.read!() |> String.split(~r/^---\n/m, parts: 3)
    front
  end

  # %{"project" => "<query text>", ...} from the `sparql:` mapping of one template.
  defp inline_queries(path) do
    lines = path |> frontmatter() |> String.split("\n")

    lines
    |> Enum.drop_while(&(&1 != "sparql:"))
    |> Enum.drop(1)
    |> Enum.take_while(&(String.starts_with?(&1, "  ") or &1 == ""))
    |> Enum.chunk_while(
      nil,
      fn line, acc ->
        case {Regex.run(~r/^  (\w+): \|$/, line), acc} do
          {[_, name], nil} -> {:cont, {name, []}}
          {[_, name], {prev, body}} -> {:cont, {prev, Enum.reverse(body)}, {name, []}}
          {nil, {name, body}} -> {:cont, {name, [String.replace_prefix(line, "    ", "") | body]}}
        end
      end,
      fn
        nil -> {:cont, nil}
        {name, body} -> {:cont, {name, Enum.reverse(body)}, nil}
      end
    )
    |> Map.new(fn {name, body} -> {name, body |> Enum.join("\n") |> String.trim_trailing("\n")} end)
  end

  test "positive control: the templates and queries exist and the parser sees the inline SELECTs" do
    assert length(@templates) >= 13
    assert length(@queries) >= 4

    mix = inline_queries("templates/mix.exs.tmpl")
    assert Map.keys(mix) == ["project"]
    assert mix["project"] =~ "SELECT ?package_version"
  end

  test "every inline query is byte-identical to its queries/<name>.rq" do
    for template <- @templates, {name, inline} <- inline_queries(template) do
      file = "queries/#{name}.rq"
      assert File.exists?(file), "#{template} names query #{name}, but #{file} does not exist"

      assert inline == file |> File.read!() |> String.trim_trailing("\n"),
             "#{template}: inline `#{name}` differs from #{file}; copy the .rq into the frontmatter"
    end
  end

  test "every queries/*.rq is used by at least one template" do
    used = for template <- @templates, name <- Map.keys(inline_queries(template)), into: MapSet.new(), do: name

    for file <- @queries do
      assert Path.basename(file, ".rq") in used, "#{file} is used by no template"
    end
  end

  test "every template has exactly one output and carries the SPDX header in its body" do
    for template <- @templates do
      assert frontmatter(template) =~ ~r/^to: \S+$/m, "#{template} has no `to:`"
      body = template |> File.read!() |> String.split(~r/^---\n/m, parts: 3) |> List.last()
      # REUSE-IgnoreStart
      assert body =~ "SPDX-License-Identifier: MIT", "#{template} lacks the SPDX header"
      # REUSE-IgnoreEnd
    end
  end

  # S3 variables every consumer may rely on, exposed by queries/project.rq.
  @s3_variables ~w(package_version graphlaw_version abi_version wasm_sha256 wasm_asset wasm_url
                   docs_url repository_url maintainer date_released coverage_threshold engine_release_tag)

  defp select_variables(query) do
    [select] = Regex.run(~r/SELECT\s+(.*?)\s+WHERE/s, query, capture: :all_but_first)
    ~r/\?(\w+)/ |> Regex.scan(select, capture: :all_but_first) |> List.flatten()
  end

  defp template_body(template), do: template |> File.read!() |> String.split(~r/^---\n/m, parts: 3) |> List.last()

  test "positive control: the SELECT parser reads a known projection" do
    assert select_variables("SELECT ?a ?b\n ?c WHERE { }") == ~w(a b c)
  end

  test "queries/project.rq projects every S3 variable" do
    projected = "queries/project.rq" |> File.read!() |> select_variables()

    for var <- @s3_variables do
      assert var in projected, "queries/project.rq does not project ?#{var}"
    end
  end

  test "every projected variable is bound by a triple pattern in the WHERE clause" do
    query = File.read!("queries/project.rq")
    [_, where] = String.split(query, "WHERE", parts: 2)

    for var <- select_variables(query) do
      assert where =~ "?#{var}", "?#{var} is projected but never bound in WHERE"
    end
  end

  test "every project variable a template reads (p.<var>) is projected by queries/project.rq" do
    projected = "queries/project.rq" |> File.read!() |> select_variables() |> MapSet.new()

    for template <- @templates,
        [_, var] <- Regex.scan(~r/\bp\.(\w+)/, template_body(template)) do
      assert var in projected, "#{template} reads p.#{var}, which queries/project.rq does not project"
    end
  end
end
