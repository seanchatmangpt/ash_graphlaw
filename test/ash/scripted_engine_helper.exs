# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# UNSUPPORTED(generator-capability): hand-written test helper shared by the wasm-free files in
# test/ash. Load it with `Code.require_file("scripted_engine_helper.exs", __DIR__)`; it is
# idempotent, so every file that needs it can require it.
#
# WHY A SCRIPTED ENGINE (named exception to "real collaborators"): the pinned GraphLaw wasm is not
# vendored in every checkout, and the admission code paths under test here (evidence assembly,
# refusal mapping, lease forwarding, telemetry, atomic behavior) are not engine-side. The real
# engine cannot run in-process without the vendored binary, and a real degraded alternative does
# not exist for an op-level answer. So this is a hand-written REAL GenServer that speaks the
# `AshGraphLaw.Host` call protocol (`{:request, body, op, timeout}`, `:info`, `:status`), decodes
# the real JSON request the library encodes, and answers with a real engine-shaped response map.
# It is a simple fake, not a mock: it never asserts on interactions itself; tests assert on the
# final state the library produced (evidence, refusals, telemetry), and may read the requests it
# received as recorded protocol state. The `:wasm` tests keep exercising the real engine.

defmodule AshGraphLaw.Test.ScriptedEngine do
  @moduledoc false
  use GenServer

  @default_sha String.duplicate("ab", 32)

  @doc "Child spec so the engine can be started with `start_supervised!/1`."
  def child_spec(opts) do
    %{id: {__MODULE__, Keyword.fetch!(opts, :name)}, start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Starts a named scripted engine.

  Options: `:name` (required), `:script` (a 1-arity function from the decoded request map to
  `{:ok, response_map}` or `{:error, %AshGraphLaw.Refusal{}}`; default `admit_all/0`), `:wasm_sha256`.
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)

    GenServer.start_link(
      __MODULE__,
      %{
        script: Keyword.get(opts, :script, admit_all()),
        sha: Keyword.get(opts, :wasm_sha256, @default_sha),
        requests: [],
        timeouts: []
      },
      name: name
    )
  end

  @doc "The sha256 the engine reports through `:info` unless overridden."
  def default_sha, do: @default_sha

  @doc "Requests received so far, oldest first (decoded JSON maps)."
  def requests(server), do: GenServer.call(server, :requests)

  @doc "Per-call timeouts (ms) received so far, oldest first."
  def timeouts(server), do: GenServer.call(server, :timeouts)

  @doc "Script: every request is admitted with one receipt per step."
  def admit_all do
    fn request ->
      steps = Map.get(request, "steps", [])

      receipts =
        steps
        |> Enum.with_index()
        |> Enum.map(fn {step, index} ->
          %{
            "step" => Map.get(step, "step"),
            "parent" => "state-#{index}",
            "child" => "state-#{index + 1}",
            "added" => 0,
            "index" => index
          }
        end)

      {:ok,
       %{
         "ok" => true,
         "states" => Enum.map(0..length(steps), &"state-#{&1}"),
         "receipts" => receipts,
         "nquads" => ""
       }}
    end
  end

  @doc "Script: every request is answered `\"ok\" => false` with the given engine error code and kind."
  def refuse(code, kind \\ "NotSemanticContent", message \\ "scripted refusal") do
    fn _request ->
      {:ok,
       %{
         "ok" => false,
         "error" => %{
           "kind" => kind,
           "message" => message,
           "details" => if(code, do: %{"code" => code}, else: %{})
         }
       }}
    end
  end

  @doc "Script: every request fails at the transport layer with the given typed refusal."
  def transport_failure(%AshGraphLaw.Refusal{} = refusal), do: fn _request -> {:error, refusal} end

  @doc "Script: every request gets this raw (already decoded) value as the response."
  def raw(value), do: fn _request -> {:ok, value} end

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call({:request, body, _op, timeout}, _from, state) do
    request = Jason.decode!(body)

    {:reply, state.script.(request),
     %{state | requests: [request | state.requests], timeouts: [timeout | state.timeouts]}}
  end

  def handle_call(:status, _from, state), do: {:reply, {:ok, :loaded}, state}

  def handle_call(:info, _from, state),
    do: {:reply, {:ok, %{wasm_sha256: state.sha, path: "scripted://engine", recycles: 0}}, state}

  def handle_call(:requests, _from, state), do: {:reply, Enum.reverse(state.requests), state}
  def handle_call(:timeouts, _from, state), do: {:reply, Enum.reverse(state.timeouts), state}
end

defmodule AshGraphLaw.Test.Scripted.Laws do
  @moduledoc false

  defmodule Shape do
    @moduledoc false
    # A law with both callbacks: deterministic projection of the title only.
    @behaviour AshGraphLaw.Law
    @impl true
    def steps(_subject, _admission),
      do: [%{"step" => "shacl", "shapes" => "@prefix sh: <http://www.w3.org/ns/shacl#> ."}]

    @impl true
    def data(subject, _admission) do
      {:ok, %{text: "<urn:s:n> <urn:s:title> \"#{title(subject)}\" .\n", dialect: "ntriples"}}
    end

    defp title(%Ash.Changeset{} = changeset), do: Ash.Changeset.get_attribute(changeset, :title)
    defp title(%Ash.ActionInput{} = input), do: Ash.ActionInput.get_argument(input, :title)
    defp title(%Ash.Query{context: context}), do: Map.get(context, :title)
  end

  defmodule StepsOnly do
    @moduledoc false
    # No data/2: the default projection is used.
    @behaviour AshGraphLaw.Law
    @impl true
    def steps(_subject, _admission), do: [%{"step" => "plan", "plan" => %{"actions" => [], "goal" => ""}}]
  end

  defmodule DataDefault do
    @moduledoc false
    # data/2 declines with :default, so the default projection runs.
    @behaviour AshGraphLaw.Law
    @impl true
    def steps(_subject, _admission), do: [%{"step" => "n3", "rules" => "{ } => { } ."}]
    @impl true
    def data(_subject, _admission), do: :default
  end

  defmodule DataRefusal do
    @moduledoc false
    @behaviour AshGraphLaw.Law
    @impl true
    def steps(_subject, _admission), do: [%{"step" => "hooks"}]
    @impl true
    def data(_subject, _admission), do: {:error, AshGraphLaw.Refusal.new(:projection_failed, "law refused to project")}
  end

  defmodule DataRaises do
    @moduledoc false
    @behaviour AshGraphLaw.Law
    @impl true
    def steps(_subject, _admission), do: [%{"step" => "hooks"}]
    @impl true
    def data(_subject, _admission), do: raise("law data exploded")
  end

  defmodule DataJunk do
    @moduledoc false
    # data/2 returns something that is neither {:ok, data} nor a refusal: treated as :default.
    @behaviour AshGraphLaw.Law
    @impl true
    def steps(_subject, _admission), do: [%{"step" => "hooks"}]
    @impl true
    def data(_subject, _admission), do: :not_a_projection
  end

  defmodule StepsNotList do
    @moduledoc false
    @behaviour AshGraphLaw.Law
    @impl true
    def steps(_subject, _admission), do: :nope
  end

  defmodule StepsRaises do
    @moduledoc false
    @behaviour AshGraphLaw.Law
    @impl true
    def steps(_subject, _admission), do: raise(ArgumentError, "law steps exploded")
  end

  defmodule StepsRefusal do
    @moduledoc false
    @behaviour AshGraphLaw.Law
    @impl true
    def steps(_subject, _admission), do: {:error, AshGraphLaw.Refusal.new(:law_module_failed, "law declined to plan")}
  end

  defmodule Vanishing do
    @moduledoc false
    # Compiled with the resource, then removed from the VM by the test that needs a law module
    # that is present at compile time and gone at run time.
    @behaviour AshGraphLaw.Law
    @impl true
    def steps(_subject, _admission), do: [%{"step" => "hooks"}]
  end
end

defmodule AshGraphLaw.Test.Scripted.Projections do
  @moduledoc false

  defmodule Good do
    @moduledoc false
    @behaviour AshGraphLaw.Projection
    @impl true
    def data(_subject, _opts), do: {:ok, %{text: "<urn:p:s> <urn:p:p> \"custom\" .\n", dialect: "ntriples"}}
  end

  defmodule Garbage do
    @moduledoc false
    @behaviour AshGraphLaw.Projection
    @impl true
    def data(_subject, _opts), do: :garbage
  end

  defmodule Refusing do
    @moduledoc false
    @behaviour AshGraphLaw.Projection
    @impl true
    def data(_subject, _opts),
      do: {:error, AshGraphLaw.Refusal.new(:projection_failed, "projection refused this subject")}
  end

  defmodule Raises do
    @moduledoc false
    @behaviour AshGraphLaw.Projection
    @impl true
    def data(_subject, _opts), do: raise("projection exploded")
  end
end

defmodule AshGraphLaw.Test.Scripted.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshGraphLaw.Test.Scripted.Note
  end
end

defmodule AshGraphLaw.Test.Scripted.Note do
  @moduledoc """
  UNSUPPORTED(generator-capability): fixture resource for the wasm-free admission tests.

  Every gated action addresses the scripted engine through the `:server` option, so no pool and
  no vendored wasm is needed. Ungated actions (`:plain*`) exist so tests can build real stored
  records and real changesets/queries/inputs to run an admission against directly.
  """

  use Ash.Resource,
    domain: AshGraphLaw.Test.Scripted.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGraphLaw.Resource]

  alias AshGraphLaw.Test.Scripted.{Laws, Projections}

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  actions do
    defaults [:read]

    create :plain do
      accept [:title]
    end

    update :plain_update do
      require_atomic? false
      accept [:title]
    end

    read :plain_read

    action :plain_action, :boolean do
      argument :title, :string, public?: true
      run fn _input, _context -> {:ok, true} end
    end

    # -- Change.Admit --------------------------------------------------------
    create :change_open do
      accept [:title]
      change {AshGraphLaw.Change.Admit, admission: :open, server: AshGraphLaw.Test.ScriptedEngine.Main}
    end

    create :change_open_txn do
      accept [:title]

      change {AshGraphLaw.Change.Admit,
              admission: :open, server: AshGraphLaw.Test.ScriptedEngine.Main, phase: :before_transaction}
    end

    create :change_construct do
      accept [:title]
      change {AshGraphLaw.Change.Admit, admission: :construct_gate, server: AshGraphLaw.Test.ScriptedEngine.Main}
    end

    create :change_lease_key do
      accept [:title]

      change {AshGraphLaw.Change.Admit,
              admission: :construct_gate, server: AshGraphLaw.Test.ScriptedEngine.Main, lease_key: :my_lease}
    end

    create :change_shape do
      accept [:title]
      change {AshGraphLaw.Change.Admit, admission: :shape, server: AshGraphLaw.Test.ScriptedEngine.Main}
    end

    create :change_absent_server do
      accept [:title]
      change {AshGraphLaw.Change.Admit, admission: :open, server: AshGraphLaw.Test.ScriptedEngine.Absent}
    end

    update :change_update do
      require_atomic? false
      accept [:title]
      change {AshGraphLaw.Change.Admit, admission: :open, server: AshGraphLaw.Test.ScriptedEngine.Main}
    end

    destroy :change_destroy do
      require_atomic? false
      change {AshGraphLaw.Change.Admit, admission: :open, server: AshGraphLaw.Test.ScriptedEngine.Main}
    end

    # -- Validation.Admissible ----------------------------------------------
    create :validated do
      accept [:title]
      validate {AshGraphLaw.Validation.Admissible, admission: :open, server: AshGraphLaw.Test.ScriptedEngine.Main}
    end

    create :validated_lease_key do
      accept [:title]

      validate {AshGraphLaw.Validation.Admissible,
                admission: :construct_gate, server: AshGraphLaw.Test.ScriptedEngine.Main, lease_key: :my_lease}
    end

    # -- Preparation.Admit ---------------------------------------------------
    read :prepared do
      prepare {AshGraphLaw.Preparation.Admit, admission: :open, server: AshGraphLaw.Test.ScriptedEngine.Main}
    end

    read :prepared_lease_key do
      prepare {AshGraphLaw.Preparation.Admit,
               admission: :construct_gate, server: AshGraphLaw.Test.ScriptedEngine.Main, lease_key: :my_lease}
    end

    action :prepared_action, :boolean do
      argument :title, :string, public?: true
      prepare {AshGraphLaw.Preparation.Admit, admission: :open, server: AshGraphLaw.Test.ScriptedEngine.Main}
      run fn _input, _context -> {:ok, true} end
    end
  end

  graphlaw do
    runtime do
      timeout_ms(2500)
      max_skew_secs(30)
      trusted_keys([AshGraphLaw.Test.Lease.public_key_hex(:trusted)])
    end

    admission :open do
      step(:rdfs)
      ceiling(:observe)
    end

    admission :select_gate do
      step(:owl_rl)
      ceiling(:select)
    end

    # No `ceiling`: the DSL default (:construct) applies.
    admission :construct_gate do
      step(:rdfs)
    end

    admission :shape do
      step(:shacl)
      ceiling(:observe)
      law(Laws.Shape)
    end

    admission :steps_only do
      step(:plan)
      ceiling(:observe)
      law(Laws.StepsOnly)
    end

    admission :data_default do
      step(:n3)
      ceiling(:observe)
      law(Laws.DataDefault)
    end

    admission :data_refusal do
      step(:hooks)
      ceiling(:observe)
      law(Laws.DataRefusal)
    end

    admission :data_raises do
      step(:hooks)
      ceiling(:observe)
      law(Laws.DataRaises)
    end

    admission :data_junk do
      step(:hooks)
      ceiling(:observe)
      law(Laws.DataJunk)
    end

    admission :steps_not_list do
      step(:hooks)
      ceiling(:observe)
      law(Laws.StepsNotList)
    end

    admission :steps_raises do
      step(:hooks)
      ceiling(:observe)
      law(Laws.StepsRaises)
    end

    admission :steps_refusal do
      step(:hooks)
      ceiling(:observe)
      law(Laws.StepsRefusal)
    end

    admission :vanishing do
      step(:hooks)
      ceiling(:observe)
      law(Laws.Vanishing)
    end

    admission :dsl_projection do
      step(:rdfs)
      ceiling(:observe)
      projection(Projections.Good)
    end

    admission :garbage_projection do
      step(:rdfs)
      ceiling(:observe)
      projection(Projections.Garbage)
    end

    admission :refusing_projection do
      step(:rdfs)
      ceiling(:observe)
      projection(Projections.Refusing)
    end

    admission :raising_projection do
      step(:rdfs)
      ceiling(:observe)
      projection(Projections.Raises)
    end
  end
end

defmodule AshGraphLaw.Test.Scripted do
  @moduledoc false

  alias AshGraphLaw.Test.Scripted.Note

  @doc "Fixed registered name of the scripted engine every gated action addresses."
  def engine, do: AshGraphLaw.Test.ScriptedEngine.Main

  @doc "A real create changeset on the ungated `:plain` action."
  def changeset(title \\ "hello", context \\ %{}) do
    Ash.Changeset.for_create(Note, :plain, %{title: title}, context: context)
  end

  @doc "A real read query on the ungated `:plain_read` action."
  def query(context \\ %{}), do: Ash.Query.for_read(Note, :plain_read, %{}, context: context)

  @doc "A real generic-action input on the ungated `:plain_action` action."
  def input(title \\ "hello", context \\ %{}) do
    Ash.ActionInput.for_action(Note, :plain_action, %{title: title}, context: context)
  end

  @doc "sha256 hex of `text`."
  def sha256(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)

  @doc "The change/validation/preparation options that point an admission at the scripted engine."
  def opts(admission, extra \\ []), do: Keyword.merge([admission: admission, server: engine()], extra)
end
