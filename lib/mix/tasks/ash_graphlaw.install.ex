if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshGraphlaw.Install do
    @moduledoc """
    Installs `ash_graphlaw` into the current project: adds the formatter plugin,
    and patches the target resource module to add
    `extensions: [AshGraphLaw.Resource]` plus a starter `:graphlaw` block.
    """
    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :ash_graphlaw,
        example: "mix ash_graphlaw.install --target MyApp.SomeResource",
        positional: [],
        schema: [target: :string],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      base =
        igniter
        |> Igniter.Project.Deps.add_dep({:wasmex, "~> 0.15"})
        |> Igniter.Project.Formatter.import_dep(:ash_graphlaw)
        |> Igniter.Project.Formatter.add_formatter_plugin(AshGraphLaw.Formatter)

      case igniter.args.options[:target] do
        nil ->
          # No --target given (e.g. plain `mix igniter.install ash_graphlaw`) --
          # formatter is still wired up automatically; the resource/domain patch needs a
          # target module, so fall back to a real, disclosed manual-instructions notice
          # rather than guessing which module to patch.
          Igniter.add_notice(base, """
          AshGraphLaw.Resource installed successfully!

          Add `extensions: [AshGraphLaw.Resource]` to your Ash.Resource modules:

              use Ash.Resource,
                extensions: [AshGraphLaw.Resource]

              graphlaw do
              end

          Or re-run with `--target MyApp.SomeResource` to patch a specific module automatically.
          """)

        target ->
          target_module = Igniter.Project.Module.parse(target)

          base
          |> Spark.Igniter.add_extension(target_module, Ash.Resource, :extensions, AshGraphLaw.Resource)
          |> Igniter.Project.Module.find_and_update_module!(target_module, &add_starter_dsl_block/1)
      end
    end

    # Adds a minimal, real starter block for the primary section so the target module
    # compiles immediately after install rather than needing hand-authored DSL content.
    # Skipped when a `graphlaw` block already exists, so a second run is a no-op.
    defp add_starter_dsl_block(zipper) do
      already? =
        zipper
        |> Sourceror.Zipper.node()
        |> Sourceror.to_string()
        |> String.contains?("graphlaw do")

      if already? do
        {:ok, zipper}
      else
        {:ok,
         Igniter.Code.Common.add_code(
           zipper,
           """
           graphlaw do
           end
           """,
           placement: :after
         )}
      end
    end
  end
else
  defmodule Mix.Tasks.AshGraphlaw.Install do
    @moduledoc "Installs `ash_graphlaw` -- Igniter is not a dependency of this project, so this task prints manual instructions instead of patching files."
    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().info("""
      AshGraphLaw.Resource: Igniter is not installed, so `ash_graphlaw.install` cannot
      patch files automatically. Add `extensions: [AshGraphLaw.Resource]` to your
      Ash.Resource modules by hand:

          use Ash.Resource,
            extensions: [AshGraphLaw.Resource]

          graphlaw do
          end
      """)
    end
  end
end
